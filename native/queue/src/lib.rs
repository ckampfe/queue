use rustler::env::SavedTerm;
use rustler::{Env, NifStruct, OwnedEnv, Resource, ResourceArc, Term};
use std::cmp::min;
use std::collections::VecDeque;
use std::ops::Range;
use std::sync::Mutex;

const SLAB_SIZE: usize = 2usize.pow(12);

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
        let mut slabs = VecDeque::new();
        slabs.push_back(Slab::new());

        Self {
            slabs,
            front_slab_position: 0,
            end_slab_position: 0,
        }
    }

    /// write terms to slabs in bulk,
    /// first preallocating the memory for any slabs needed
    /// to fully accomodate the terms
    fn extend(&mut self, terms: &[Term]) {
        self.reserve_slabs(terms.len());

        let mut position_in_terms_start: usize = 0;
        let mut position_in_terms_end: usize;

        for range_in_slab in SlabRangerator::new(self.end_slab_position, terms.len()) {
            let slab = if let Some(slab) = self.slabs.back_mut() {
                slab
            } else {
                self.slabs.push_back_mut(Slab::new())
            };

            let length_to_write = range_in_slab.end - range_in_slab.start;
            position_in_terms_end = position_in_terms_start + length_to_write;
            slab.write(&terms[position_in_terms_start..position_in_terms_end]);

            position_in_terms_start = position_in_terms_end;

            if range_in_slab.end >= SLAB_SIZE {
                self.slabs.push_back(Slab::new());
                self.end_slab_position = 0;
            } else {
                self.end_slab_position += length_to_write;
            }
        }
    }

    /// reserve the minimum number of slabs
    /// needed to fully store up to `n` terms
    fn reserve_slabs(&mut self, n: usize) {
        let last_slab_remaining_capacity = SLAB_SIZE - self.end_slab_position;

        let new_slabs_required = n
            .saturating_sub(last_slab_remaining_capacity)
            .div_ceil(SLAB_SIZE);

        self.slabs.reserve_exact(new_slabs_required);
    }

    fn push_back(&mut self, term: &Term) {
        let slab = if let Some(slab) = self.slabs.back_mut() {
            slab
        } else {
            self.slabs.push_back_mut(Slab::new())
        };

        slab.push(term);

        self.end_slab_position += 1;

        if self.end_slab_position >= SLAB_SIZE {
            self.slabs.push_back(Slab::new());
            self.end_slab_position = 0;
        }
    }

    // take elements:
    // starting from self.front_slab_position
    // until either:
    // - we have taken `n` elements
    // - we have run out of elements to take
    //
    // if we run out of elements in a slab, discard that slab and proceed to the subsequent slab
    fn take<'env>(&mut self, caller_env: Env<'env>, n: usize) -> Vec<Term<'env>> {
        let mut terms = Vec::with_capacity(min(n, self.len()));
        let mut remaining = n;

        while remaining > 0 {
            // Read as much as we can out of the current front slab.
            // `exhausted` means the front slab has no more elements to give,
            // so we should discard it and move on to the next slab.
            let (new_front_position, slab_is_exhausted) = {
                let slab = match self.slabs.front_mut() {
                    Some(slab) => slab,
                    // No slabs left at all: nothing more to take.
                    None => break,
                };

                let start = self.front_slab_position;
                let available = slab.len.saturating_sub(start);

                if available == 0 {
                    (start, true)
                } else {
                    let take_here = min(available, remaining);
                    let end = start + take_here;

                    slab.env.run(|owned| {
                        let term_iter = slab.data[start..end].iter().map(|saved_term| {
                            let saved_term = saved_term.as_ref().unwrap();
                            saved_term.load(owned).in_env(caller_env)
                        });

                        terms.extend(term_iter);
                    });

                    remaining -= take_here;
                    (end, end >= slab.len)
                }
            };

            self.front_slab_position = new_front_position;

            if slab_is_exhausted {
                // Discard the drained slab, always — including the last one.
                self.slabs.pop_front();
                self.front_slab_position = 0;

                // If that emptied the queue, reset the write position too so the
                // next push_back starts a fresh slab from the beginning.
                if self.slabs.is_empty() {
                    self.end_slab_position = 0;
                }
            }
        }

        terms
    }

    // like `take`, but reads every remaining element and leaves the slabs untouched:
    // start at self.front_slab_position in the front slab, then read each
    // subsequent slab in full.
    fn as_vec<'env>(&mut self, caller_env: Env<'env>) -> Vec<Term<'env>> {
        let mut terms = Vec::with_capacity(self.len());

        for (i, slab) in self.slabs.iter().enumerate() {
            let start = if i == 0 { self.front_slab_position } else { 0 };

            if start >= slab.len {
                continue;
            }

            slab.env.run(|owned| {
                let term_iter = slab.data[start..slab.len].iter().map(|saved_term| {
                    let saved_term = saved_term.as_ref().unwrap();
                    saved_term.load(owned).in_env(caller_env)
                });

                terms.extend(term_iter);
            });
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
    data: [Option<SavedTerm>; SLAB_SIZE],
    len: usize,
}

impl Slab {
    fn new() -> Self {
        Self {
            env: OwnedEnv::new(),
            data: [const { None }; SLAB_SIZE],
            len: 0,
        }
    }

    /// write the given `terms` to the slab at `self.len`
    fn write(&mut self, terms: &[Term]) {
        let saved_terms = terms.iter().map(|term| self.env.save(term));

        for (target, saved_term) in self.data[self.len..self.len + terms.len()]
            .iter_mut()
            .zip(saved_terms)
        {
            *target = Some(saved_term)
        }

        self.len += terms.len()
    }

    fn push(&mut self, term: &Term) {
        let owned_term = self.env.save(term);
        self.data[self.len] = Some(owned_term);
        self.len += 1;
    }
}

/// an iterator to emit ranges for where in slabs to write an input of
/// `remaining_input` into slabs of SLAB_SIZE,
/// starting at `position`.
///
/// see the tests for what this looks like
struct SlabRangerator {
    position: usize,
    remaining_input: usize,
}

impl SlabRangerator {
    fn new(position: usize, remaining_input: usize) -> Self {
        Self {
            position,
            remaining_input,
        }
    }
}

impl Iterator for SlabRangerator {
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

#[rustler::nif(name = "extend_impl", schedule = "DirtyCpu")]
fn extend(queue: Queue, list_of_terms: Vec<Term>) -> Queue {
    {
        let mut guard = queue.resource.inner.lock().unwrap();
        guard.extend(&list_of_terms);
    }

    queue
}

#[rustler::nif]
fn pop_front<'env>(env: Env<'env>, queue: Queue) -> Option<Term<'env>> {
    let mut guard = queue.resource.inner.lock().unwrap();
    guard.take(env, 1).pop()
}

#[rustler::nif(name = "take_impl", schedule = "DirtyCpu")]
fn take<'env>(env: Env<'env>, queue: Queue, n: usize) -> Vec<Term<'env>> {
    let mut guard = queue.resource.inner.lock().unwrap();
    guard.take(env, n)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn to_list<'env>(env: Env<'env>, queue: Queue) -> Vec<Term<'env>> {
    let mut guard = queue.resource.inner.lock().unwrap();
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
    use crate::SlabRangerator;

    #[test]
    fn rangerator_test() {
        let ranges: Vec<_> = SlabRangerator::new(0, 4000).into_iter().collect();
        assert_eq!(ranges, vec![0..4000]);

        let ranges: Vec<_> = SlabRangerator::new(4000, 1000).into_iter().collect();
        assert_eq!(ranges, vec![4000..4096, 0..904]);

        let ranges: Vec<_> = SlabRangerator::new(4000, 5000).into_iter().collect();
        assert_eq!(ranges, vec![4000..4096, 0..4096, 0..808]);
    }
}
