use rustler::{Env, NifStruct, OwnedEnv, Resource, ResourceArc, Term};
use std::cmp::min;
use std::collections::VecDeque;
use std::marker::PhantomData;
use std::ops::Range;
use std::sync::Mutex;

// More or less a raw pointer to a BEAM term.
// See `Slab` for details of lifetime/safety.
type NifTerm = usize;

const SLAB_SIZE: usize = envparse::parse_env!("QUEUE_NIF_SLAB_SIZE" as usize (in 1..) else 4096);

#[derive(NifStruct)]
#[module = "Queue"]
struct Queue {
    resource: ResourceArc<QueueResource>,
}

struct QueueResource {
    inner: Mutex<QueueImpl>,
}

struct QueueImpl {
    slabs: VecDeque<Slab>,
    front_slab_position: usize,
    end_slab_position: usize,
}

impl QueueImpl {
    fn new() -> Self {
        let slabs = VecDeque::from([Slab::new()]);

        Self {
            slabs,
            front_slab_position: 0,
            end_slab_position: 0,
        }
    }

    /// write terms to slabs in bulk,
    /// first preallocating the memory for any slabs needed
    /// to fully accomodate the terms
    fn extend_back(&mut self, terms: &[Term]) {
        if terms.is_empty() {
            return;
        }

        self.reserve_slabs_back(terms.len());

        let mut position_in_terms_start: usize = 0;
        let mut position_in_terms_end: usize;

        for range_in_slab in SlabRangerator::<Back>::new(self.end_slab_position, terms.len()) {
            let slab = if let Some(slab) = self.slabs.back_mut() {
                slab
            } else {
                self.slabs.push_back_mut(Slab::new())
            };

            let length_to_write = range_in_slab.end - range_in_slab.start;
            position_in_terms_end = position_in_terms_start + length_to_write;
            slab.write_many(
                self.end_slab_position,
                &terms[position_in_terms_start..position_in_terms_end],
            );
            self.end_slab_position += length_to_write;

            position_in_terms_start = position_in_terms_end;

            if range_in_slab.end >= SLAB_SIZE {
                self.slabs.push_back(Slab::new());
                self.end_slab_position = 0;
            }
        }
    }

    /// like `extend_back`, but writing towards the front of the queue.
    ///
    /// each term is prepended in list order, so the batch lands in the queue
    /// reversed: the last term of `terms` ends up nearest the old front.
    fn extend_front(&mut self, terms: &[Term]) {
        if terms.is_empty() {
            return;
        }

        self.reserve_slabs_front(terms.len());

        // an empty queue has no slab to write into. start one and fill it from
        // the top down, so the (empty) back of the queue stays at the slab's end.
        if self.slabs.is_empty() {
            self.slabs.push_back(Slab::new());
            self.front_slab_position = SLAB_SIZE;
            self.end_slab_position = SLAB_SIZE;
        }

        let mut position_in_terms_start: usize = 0;
        let mut position_in_terms_end: usize;

        for range_in_slab in SlabRangerator::<Front>::new(self.front_slab_position, terms.len()) {
            let slab = if let Some(slab) = self.slabs.front_mut() {
                slab
            } else {
                self.slabs.push_front_mut(Slab::new())
            };

            let length_to_write = range_in_slab.end - range_in_slab.start;
            position_in_terms_end = position_in_terms_start + length_to_write;
            slab.write_many_rev(
                range_in_slab.start,
                &terms[position_in_terms_start..position_in_terms_end],
            );
            self.front_slab_position = range_in_slab.start;

            position_in_terms_start = position_in_terms_end;

            if range_in_slab.start == 0 {
                self.slabs.push_front(Slab::new());
                self.front_slab_position = SLAB_SIZE;
            }
        }
    }

    /// reserve the minimum number of slabs
    /// needed to fully store up to `n` terms
    fn reserve_slabs_back(&mut self, n: usize) {
        let last_slab_remaining_capacity = SLAB_SIZE - self.end_slab_position;

        let new_slabs_required = n
            .saturating_sub(last_slab_remaining_capacity)
            .div_ceil(SLAB_SIZE);

        self.slabs.reserve_exact(new_slabs_required);
    }

    /// reserve the minimum number of slabs
    /// needed to fully store up to `n` terms
    fn reserve_slabs_front(&mut self, n: usize) {
        let front_slab_remaining_capacity = self.front_slab_position;

        let new_slabs_required = n
            .saturating_sub(front_slab_remaining_capacity)
            .div_ceil(SLAB_SIZE);

        self.slabs.reserve_exact(new_slabs_required);
    }

    fn push_back(&mut self, term: &Term) {
        let slab = if let Some(slab) = self.slabs.back_mut() {
            slab
        } else {
            self.end_slab_position = 0;
            self.slabs.push_back_mut(Slab::new())
        };

        slab.write_one(self.end_slab_position, term);
        self.end_slab_position += 1;

        if self.end_slab_position >= SLAB_SIZE {
            self.slabs.push_back(Slab::new());
            self.end_slab_position = 0;
        }
    }

    fn push_front(&mut self, term: &Term) {
        if self.slabs.is_empty() {
            self.slabs.push_back(Slab::new());
            self.front_slab_position = SLAB_SIZE;
            self.end_slab_position = SLAB_SIZE;
        }

        if self.front_slab_position == 0 {
            self.slabs.push_front(Slab::new());
            self.front_slab_position = SLAB_SIZE;
        }

        self.front_slab_position -= 1;

        let slab = if let Some(slab) = self.slabs.front_mut() {
            slab
        } else {
            self.slabs.push_front_mut(Slab::new())
        };

        slab.write_one(self.front_slab_position, term);
    }

    // take elements:
    // starting from self.front_slab_position
    // until either:
    // - we have taken `n` elements
    // - we have run out of elements to take
    //
    // if we run out of elements in a slab, discard that slab and proceed to the subsequent slab
    fn take_front<'env>(&mut self, caller_env: Env<'env>, n: usize) -> Vec<Term<'env>> {
        let mut terms = Vec::with_capacity(min(n, self.len()));
        let mut remaining = n;
        let mut is_last_slab = self.slabs.len() == 1;

        while remaining > 0 {
            // Read as much as we can out of the current front slab.
            // `exhausted` means the front slab has no more elements to give,
            // so we should discard it and move on to the next slab.
            let (new_front_position, slab_is_exhausted) = {
                let slab = match self.slabs.front_mut() {
                    Some(slab) => slab,
                    None => break,
                };

                let start = self.front_slab_position;

                let available = if is_last_slab {
                    self.end_slab_position.saturating_sub(start)
                } else {
                    SLAB_SIZE.saturating_sub(start)
                };

                if available == 0 {
                    (start, true)
                } else {
                    let take_here = min(available, remaining);
                    let end = start + take_here;

                    slab.copy_many_out_of(start..end, &mut terms, caller_env);

                    remaining -= take_here;
                    (
                        end,
                        if is_last_slab {
                            end >= self.end_slab_position
                        } else {
                            end >= SLAB_SIZE
                        },
                    )
                }
            };

            self.front_slab_position = new_front_position;

            if slab_is_exhausted {
                // Discard the drained slab, always — including the last one.
                self.slabs.pop_front();
                self.front_slab_position = 0;
                is_last_slab = self.slabs.len() == 1;

                if self.slabs.is_empty() {
                    self.end_slab_position = 0;
                }
            }
        }

        terms
    }

    fn peek_front<'env>(&self, caller_env: Env<'env>) -> Option<Term<'env>> {
        if let Some(slab) = self.slabs.front()
            && self.len() != 0
        {
            Some(slab.copy_one_out_of(self.front_slab_position, caller_env))
        } else {
            None
        }
    }

    fn peek_back<'env>(&self, caller_env: Env<'env>) -> Option<Term<'env>> {
        if self.len() == 0 {
            return None;
        }

        // `end_slab_position` is one past the last element. when it is 0
        // the back slab is empty, and the last live element is the
        // final slot of the slab before it.
        let (slab, position) = if self.end_slab_position == 0 {
            (self.slabs.get(self.slabs.len() - 2)?, SLAB_SIZE - 1)
        } else {
            (self.slabs.back()?, self.end_slab_position - 1)
        };

        Some(slab.copy_one_out_of(position, caller_env))
    }

    // like `take`, but reads every remaining element and leaves the slabs untouched:
    // start at self.front_slab_position in the front slab, then read each
    // subsequent slab in full, up to `self.end_slab_position` in the last slab.
    fn as_vec<'env>(&self, caller_env: Env<'env>) -> Vec<Term<'env>> {
        let mut terms = Vec::with_capacity(self.len());

        let slabs_len = self.slabs.len();

        for (i, slab) in self.slabs.iter().enumerate() {
            let is_first_slab = i == 0;
            let is_last_slab = i == slabs_len - 1;
            let start = if is_first_slab {
                self.front_slab_position
            } else {
                0
            };

            if is_last_slab && start >= self.end_slab_position {
                continue;
            }

            let to_take = if is_last_slab {
                start..self.end_slab_position
            } else {
                start..SLAB_SIZE
            };

            slab.copy_many_out_of(to_take, &mut terms, caller_env);
        }

        terms
    }

    // every element written across all slabs, minus the ones already consumed
    // out of the front slab.
    fn len(&self) -> usize {
        if self.slabs.is_empty() {
            0
        } else {
            ((self.slabs.len() - 1) * SLAB_SIZE + self.end_slab_position)
                .saturating_sub(self.front_slab_position)
        }
    }
}

struct Slab {
    env: OwnedEnv,
    data: [NifTerm; SLAB_SIZE],
}

impl Slab {
    fn new() -> Self {
        Self {
            env: OwnedEnv::new(),
            data: [0; SLAB_SIZE],
        }
    }

    /// write the given `terms` to the slab at `self.len`
    ///
    /// SAFETY:
    ///
    /// in_env copies the term into env.
    /// the term's lifetime is bound by env.
    /// env's lifetime is the slab's lifetime,
    /// so when the slab is freed, env is freed,
    /// and the terms in it are freed.
    ///
    /// therefor the slab owns the terms
    fn write_many(&mut self, begin: usize, terms: &[Term]) {
        let Slab { env, data } = self;

        env.run(|env| {
            for (target, term) in data[begin..begin + terms.len()].iter_mut().zip(terms) {
                *target = term.in_env(env).as_c_arg();
            }
        });
    }

    /// write the given terms in reverse at the given location.
    fn write_many_rev(&mut self, begin: usize, terms: &[Term]) {
        let Slab { env, data } = self;

        env.run(|env| {
            for (target, term) in data[begin..begin + terms.len()].iter_mut().rev().zip(terms) {
                *target = term.in_env(env).as_c_arg();
            }
        });
    }

    /// write a single term into `position`
    ///
    /// SAFETY:
    ///
    /// same as `write_many`
    fn write_one(&mut self, position: usize, term: &Term) {
        self.data[position] = self.env.run(|env| term.in_env(env).as_c_arg());
    }

    fn copy_one_out_of<'a>(&self, position: usize, target_env: Env<'a>) -> Term<'a> {
        self.env.run(|owned_env| {
            let saved_term = self.data[position];
            unsafe { Term::new(owned_env, saved_term) }.in_env(target_env)
        })
    }

    /// Extend `target` with terms from the slab, at `range`.
    ///
    /// terms are copied into `target_env`.
    ///
    /// Does not modify the slab.
    ///
    /// SAFETY: copying the terms from the slab is safe because the terms
    /// exist in the env on the slab. If the slab live, the env is live,
    /// and the terms are live.
    fn copy_many_out_of<'a>(
        &self,
        range: Range<usize>,
        out: &mut Vec<Term<'a>>,
        target_env: Env<'a>,
    ) {
        self.env.run(|owned_env| {
            let term_iter = self.data[range]
                .iter()
                .map(|saved_term| unsafe { Term::new(owned_env, *saved_term) }.in_env(target_env));

            out.extend(term_iter);
        });
    }
}

struct Front;
struct Back;

/// an iterator to emit ranges for where in slabs to write an input of
/// `remaining_input` into slabs of SLAB_SIZE,
/// starting at `position`.
///
/// see the tests for what this looks like
struct SlabRangerator<DIRECTION> {
    position: usize,
    remaining_input: usize,
    _direction: PhantomData<DIRECTION>,
}

impl<DIRECTION> SlabRangerator<DIRECTION> {
    fn new(position: usize, remaining_input: usize) -> Self {
        Self {
            position,
            remaining_input,
            _direction: PhantomData,
        }
    }
}

impl Iterator for SlabRangerator<Back> {
    type Item = Range<usize>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.remaining_input > 0 {
            let available = SLAB_SIZE - self.position;

            let range_start = self.position;

            let range_end = range_start + min(available, self.remaining_input);

            if range_end == SLAB_SIZE {
                self.position = 0;
            } else {
                self.position = range_end;
            }

            self.remaining_input -= range_end - range_start;

            Some(range_start..range_end)
        } else {
            None
        }
    }
}

impl Iterator for SlabRangerator<Front> {
    type Item = Range<usize>;

    /// each range is ascending, like the `Back` ranges, but they are yielded
    /// walking towards the front: the first range is the one that ends at
    /// `position`, and each subsequent range is in the slab before it.
    fn next(&mut self) -> Option<Self::Item> {
        if self.remaining_input > 0 {
            let range_end = self.position;
            let range_start = range_end.saturating_sub(self.remaining_input);

            if range_start == 0 {
                self.position = SLAB_SIZE;
            } else {
                self.position = range_start;
            }

            self.remaining_input -= range_end - range_start;

            Some(range_start..range_end)
        } else {
            None
        }
    }
}

#[rustler::resource_impl]
impl Resource for QueueResource {}

#[rustler::nif]
fn new() -> Queue {
    Queue {
        resource: ResourceArc::new(QueueResource {
            inner: Mutex::new(QueueImpl::new()),
        }),
    }
}

#[rustler::nif]
fn push_back(queue: Queue, term: Term) -> Queue {
    {
        let mut guard = queue.resource.inner.lock().unwrap();
        guard.push_back(&term);
    }

    queue
}

#[rustler::nif]
fn push_front(queue: Queue, term: Term) -> Queue {
    {
        let mut guard = queue.resource.inner.lock().unwrap();
        guard.push_front(&term);
    }

    queue
}

#[rustler::nif(name = "extend_back_impl", schedule = "DirtyCpu")]
fn extend_back(queue: Queue, list_of_terms: Vec<Term>) -> Queue {
    {
        let mut guard = queue.resource.inner.lock().unwrap();
        guard.extend_back(&list_of_terms);
    }

    queue
}

#[rustler::nif(name = "extend_front_impl", schedule = "DirtyCpu")]
fn extend_front(queue: Queue, list_of_terms: Vec<Term>) -> Queue {
    {
        let mut guard = queue.resource.inner.lock().unwrap();
        guard.extend_front(&list_of_terms);
    }

    queue
}

#[rustler::nif]
fn pop_front<'env>(env: Env<'env>, queue: Queue) -> Option<Term<'env>> {
    let mut guard = queue.resource.inner.lock().unwrap();
    guard.take_front(env, 1).pop()
}

#[rustler::nif]
fn take_front_small<'env>(env: Env<'env>, queue: Queue, n: usize) -> Vec<Term<'env>> {
    let mut guard = queue.resource.inner.lock().unwrap();
    guard.take_front(env, n)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn take_front_large<'env>(env: Env<'env>, queue: Queue, n: usize) -> Vec<Term<'env>> {
    let mut guard = queue.resource.inner.lock().unwrap();
    guard.take_front(env, n)
}

#[rustler::nif]
fn peek_front<'env>(env: Env<'env>, queue: Queue) -> Option<Term<'env>> {
    let guard = queue.resource.inner.lock().unwrap();
    guard.peek_front(env)
}

#[rustler::nif]
fn peek_back<'env>(env: Env<'env>, queue: Queue) -> Option<Term<'env>> {
    let guard = queue.resource.inner.lock().unwrap();
    guard.peek_back(env)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn to_list<'env>(env: Env<'env>, queue: Queue) -> Vec<Term<'env>> {
    let guard = queue.resource.inner.lock().unwrap();
    guard.as_vec(env)
}

#[rustler::nif]
fn count(queue: Queue) -> usize {
    let guard = queue.resource.inner.lock().unwrap();
    guard.len()
}

rustler::init!("Elixir.Queue");

#[cfg(test)]
mod tests {
    //! note that these tests are defined for a slab size of 4096 and will fail
    //! with other slab sizes
    use crate::{Back, Front, SlabRangerator};

    #[test]
    fn rangerator_back_test() {
        let ranges: Vec<_> = SlabRangerator::<Back>::new(0, 4000).collect();
        assert_eq!(ranges, vec![0..4000]);

        let ranges: Vec<_> = SlabRangerator::<Back>::new(4000, 1000).collect();
        assert_eq!(ranges, vec![4000..4096, 0..904]);

        let ranges: Vec<_> = SlabRangerator::<Back>::new(4000, 5000).collect();
        assert_eq!(ranges, vec![4000..4096, 0..4096, 0..808]);
    }

    #[test]
    fn rangerator_front_test() {
        // each range is ascending, but they are yielded front-ward: the first
        // range is the one ending at the starting position.
        let ranges: Vec<_> = SlabRangerator::<Front>::new(4000, 6000).collect();
        assert_eq!(ranges, vec![0..4000, 2096..4096]);

        let ranges: Vec<_> = SlabRangerator::<Front>::new(4000, 1000).collect();
        assert_eq!(ranges, vec![3000..4000]);

        let ranges: Vec<_> = SlabRangerator::<Front>::new(100, 5000).collect();
        assert_eq!(ranges, vec![0..100, 0..4096, 3292..4096]);
    }
}
