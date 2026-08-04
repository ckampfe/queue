use rustler::{Env, NifStruct, OwnedEnv, Resource, ResourceArc, Term, env::SavedTerm};
use std::{cmp::min, collections::VecDeque, sync::Mutex};

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

    fn push_back(&mut self, term: Term) {
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
        let mut terms = Vec::new();
        let mut remaining = n;

        while remaining > 0 {
            // Read as much as we can out of the current front slab.
            // `exhausted` means the front slab has no more elements to give,
            // so we should discard it and move on to the next slab.
            let (new_front_position, slab_is_exhausted) = {
                let slab = match self.slabs.front() {
                    Some(slab) => slab,
                    // No slabs left at all: nothing more to take.
                    None => break,
                };

                let start = self.front_slab_position;
                let available = slab.data.len().saturating_sub(start);

                if available == 0 {
                    (start, true)
                } else {
                    let take_here = min(available, remaining);
                    let end = start + take_here;

                    slab.env.run(|owned| {
                        // for saved in &slab.data[start..end] {
                        //     terms.push(saved.load(owned).in_env(caller_env));
                        // }

                        let i = slab.data[start..end]
                            .iter()
                            .map(|saved_term| saved_term.load(owned).in_env(caller_env));

                        terms.extend(i);
                    });

                    remaining -= take_here;
                    (end, end >= slab.data.len())
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
    fn to_list<'env>(&self, caller_env: Env<'env>) -> Vec<Term<'env>> {
        let mut terms = Vec::new();

        for (i, slab) in self.slabs.iter().enumerate() {
            let start = if i == 0 { self.front_slab_position } else { 0 };

            if start >= slab.data.len() {
                continue;
            }

            slab.env.run(|owned| {
                let i = slab.data[start..]
                    .iter()
                    .map(|saved_term| saved_term.load(owned).in_env(caller_env));

                terms.extend(i);
            });
        }

        terms
    }

    // every element written across all slabs, minus the ones already consumed
    // out of the front slab.
    fn len(&self) -> usize {
        let written: usize = self.slabs.iter().map(|slab| slab.data.len()).sum();
        written.saturating_sub(self.front_slab_position)
    }
}

struct Slab {
    env: OwnedEnv,
    data: Vec<SavedTerm>,
}

impl Slab {
    fn new() -> Self {
        Self {
            env: OwnedEnv::new(),
            data: Vec::with_capacity(SLAB_SIZE),
        }
    }
    fn push(&mut self, term: Term) {
        let owned_term = self.env.save(term);
        self.data.push(owned_term);
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
        guard.push_back(term);
    }

    queue
}

#[rustler::nif(schedule = "DirtyCpu")]
fn push_back_n_impl(queue: Queue, list_of_terms: Vec<Term>) -> Queue {
    {
        let mut guard = queue.resource.inner.lock().unwrap();
        for term in list_of_terms {
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
    let guard = queue.resource.inner.lock().unwrap();
    guard.to_list(env)
}

#[rustler::nif]
fn count(queue: Queue) -> usize {
    let guard = queue.resource.inner.lock().unwrap();
    guard.len()
}

rustler::init!("Elixir.Queue");
