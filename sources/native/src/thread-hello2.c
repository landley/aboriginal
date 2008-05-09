// Threaded hello world program that uses mutex and event semaphores to pass
// the string to print from one thread to another, and waits for the child
// thread to return a result before exiting the program.

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Thread, semaphores, and mailbox
struct thread_info {
	pthread_t thread;
	pthread_mutex_t wakeup_mutex;
	pthread_cond_t wakeup_send, wakeup_receive;
	unsigned len;
	char *data;
};

// Create a new thread with associated resources.
struct thread_info *newthread(void *(*func)(void *))
{
	struct thread_info *ti = malloc(sizeof(struct thread_info));
	memset(ti, 0, sizeof(struct thread_info));

	pthread_create(&(ti->thread), NULL, func, ti);

	return ti;
}

// Send a block of data through mailbox.
void thread_send(struct thread_info *ti, char *data, unsigned len)
{
	pthread_mutex_lock(&(ti->wakeup_mutex));
	// If consumer hasn't consumed yet, wait for them to do so.
	if (ti->len)
		pthread_cond_wait(&(ti->wakeup_send), &(ti->wakeup_mutex));
	ti->data = data;
	ti->len = len;
	pthread_cond_signal(&(ti->wakeup_receive));
	pthread_mutex_unlock(&(ti->wakeup_mutex));
}

// Receive a block of data through mailbox.
void thread_receive(struct thread_info *ti, char **data, unsigned *len)
{
	pthread_mutex_lock(&(ti->wakeup_mutex));
	if (!ti->len)
		pthread_cond_wait(&(ti->wakeup_receive), &(ti->wakeup_mutex));
	*data = ti->data;
	*len = ti->len;
	// If sender is waiting to send us a second message, wake 'em up.
	// Note that "if (ti->len)" be used as an unlocked/nonblocking test for
	// pending data, although you still need call this function to read data.
	ti->len = 0;
	pthread_cond_signal(&(ti->wakeup_send));
	pthread_mutex_unlock(&(ti->wakeup_mutex));
}

// Function for new thread to execute.
void *hello_thread(void *thread_data)
{
	struct thread_info *ti = (struct thread_info *)thread_data;

	for (;;) {
		unsigned len;
		char *data;

		thread_receive(ti, &data, &len);
		if (!data) break;
		printf("%.*s", len, data);
		free(data);
	}

	return 0;
}

int main(int argc, char *argv[])
{
	void *result;
	char *data = strdup("Hello world!\n");
	struct thread_info *ti = newthread(hello_thread);

	// Send one line of text.
	thread_send(ti, data, strlen(data));
	// Signal thread to exit and wait for it to do so.
	thread_send(ti, NULL, 1);
	pthread_join(ti->thread, &result);

	return (long)result;
}
