typedef struct lock {
  volatile int locked;
} lock_t;

void lock_init(lock_t *lock);
void lock_acquire(lock_t *lock);
void lock_release(lock_t *lock);
int thread_create(void* (*fcn)(void*), void *arg);

