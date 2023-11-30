#!/usr/sbin/dtrace -qCs

#pragma D option bufsize=16M
#pragma D option switchrate=497hz

#define	PFX()	printf("[%8u cpu %3d tid %3d]  ",			\
		(timestamp - start) / 1000, cpu, tid);

BEGIN {
	start = timestamp;
}

syscall::lseek:entry
/pid == $target/
{
	self->ls = 1;

	PFX();
	printf("lseek entry\n");
}

sched:::off-cpu
/self->ls/
{
	PFX();
	printf("lseek going off cpu");
	stack();
	printf("\n");
}

sched:::on-cpu
/self->ls/
{
	PFX();
	printf("lseek coming on cpu");
	printf("\n");
}

syscall::lseek:return
/pid == $target/
{
	PFX();
	printf("lseek -> %d (errno %u)\n", (int)arg1, errno);

	self->ls = 0;
}

/*
 * Ignore writes to stdout/stderr, and any writes not on the main thread.
 */
syscall::write:entry
/pid == $target && arg0 > 2 && tid == 1/
{
	self->w = 1;
	self->fd = (int)arg0;

	PFX();
	printf("write(fd %d) entry [fp @ %d]\n", self->fd,
	    fds[self->fd].fi_offset);
}

syscall::write:return
/pid == $target && self->w/
{
	PFX();
	printf("write(fd %d) -> %d [fp @ %d]\n", self->fd, (int)arg1,
	    fds[self->fd].fi_offset);

	self->fd = 0;
	self->w = 0;
}
