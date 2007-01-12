#define __REENTRANT
#include <pthread.h>
#include <stdio.h>
 
void *threadhello(void *unused)
{
  printf("Hello, world!\n");
  return 0;
}
 
int main() {
  pthread_t thready;
  pthread_create(&thready, NULL, &threadhello, NULL);
  usleep(10);
}
