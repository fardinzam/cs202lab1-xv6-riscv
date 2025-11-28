#include "kernel/types.h"
#include "user/user.h"
#include "user/thread.h"

#define STACK_SIZE 4096

// Structure to pass function and argument to new thread
struct thread_args {
  void* (*fcn)(void*);
  void *arg;
};

void lock_init(lock_t *lock)
{
  lock->locked = 0;
}

void lock_acquire(lock_t *lock)
{
  while(__sync_lock_test_and_set(&lock->locked, 1) != 0)
    ; // spin
}

void lock_release(lock_t *lock)
{
  __sync_lock_release(&lock->locked);
}

int thread_create(void* (*fcn)(void*), void *arg)
{
  void *stack = malloc(STACK_SIZE);
  if(stack == 0)
    return -1;
  
  // Stack grows downward, so point to the top of the stack
  void *stack_top = (char*)stack + STACK_SIZE;
  
  // Store function and argument at a known location on the stack
  // We'll store them at the top of the stack
  struct thread_args *args = (struct thread_args*)((char*)stack_top - sizeof(struct thread_args));
  args->fcn = fcn;
  args->arg = arg;
  
  // Set child's stack pointer to point below the args (leave room for stack usage)
  // The args are at stack_top - sizeof(struct thread_args)
  // We'll set child_stack to point 16 bytes below that to leave some room
  void *child_stack = (char*)stack_top - sizeof(struct thread_args) - 16;
  
  int pid = clone(child_stack);
  
  if(pid == 0) {
    // Child thread: get args from the stack
    // The stack pointer was set to child_stack by clone()
    // Read the current stack pointer
    uint64 sp;
    __asm__ volatile("mv %0, sp" : "=r" (sp));
    
    // args are stored at: stack_top - sizeof(struct thread_args)
    // We know: child_stack = stack_top - sizeof(struct thread_args) - 16
    // So: args = (struct thread_args*)((char*)sp + 16)
    struct thread_args *my_args = (struct thread_args*)((char*)sp + 16);
    my_args->fcn(my_args->arg);
    exit(0);
  }
  
  if(pid < 0) {
    free(stack);
    return -1;
  }
  
  // Parent: return the pid
  // Note: we don't free the stack here because the child thread is using it
  return pid;
}

