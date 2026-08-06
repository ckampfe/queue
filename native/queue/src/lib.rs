use rustler::env::SavedTerm;
use rustler::{Env, NifStruct, OwnedEnv, Resource, ResourceArc, Term};
use std::cmp::min;
use std::collections::VecDeque;
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
        let written: usize = self.slabs.iter().map(|slab| slab.len).sum();
        written.saturating_sub(self.front_slab_position)
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

    // fn is_full(&self) -> bool {
    //     self.len == SLAB_SIZE
    // }

    fn push(&mut self, term: &Term) {
        let owned_term = self.env.save(term);
        self.data[self.len] = Some(owned_term);
        self.len += 1;
    }

    // way to take an entire slab and slam it into another collection
    // fn take_all<'env>(&self, caller_env: Env<'env>, out: &mut Vec<Term<'env>>) {
    //     self.env.run(|owned_env| {
    //         let iter = self.data.iter().map(|item| {
    //             let item = item.as_ref().unwrap();
    //             item.load(owned_env).in_env(caller_env)
    //         });

    //         out.extend(iter)
    //     });
    // }

    // fn take_all2<'env>(self, caller_env: Env<'env>, out: &mut Vec<Term<'env>>) {
    //     self.env.run(|owned_env| {
    //         let x = self.data.into_iter().map(|item| item.unwrap());
    //         let i = x.map(|item| item.load(owned_env).in_env(caller_env));
    //         out.extend(i);
    //     });
    // }
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

#[rustler::nif(schedule = "DirtyCpu")]
fn push_back_n_impl(queue: Queue, list_of_terms: Vec<Term>) -> Queue {
    {
        let mut guard = queue.resource.inner.lock().unwrap();

        guard.reserve_slabs(list_of_terms.len());

        for term in &list_of_terms {
            guard.push_back(term);
        }
    }

    queue
}

#[rustler::nif(schedule = "DirtyCpu")]
fn pop_front<'env>(env: Env<'env>, queue: Queue) -> Option<Term<'env>> {
    let mut guard = queue.resource.inner.lock().unwrap();
    guard.take(env, 1).pop()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn pop_front_n_impl<'env>(env: Env<'env>, queue: Queue, n: usize) -> Vec<Term<'env>> {
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
