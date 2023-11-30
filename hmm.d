#!/usr/sbin/dtrace -qCs

#define list_empty(a) ((a)->list_head.list_next == &(a)->list_head)
#define list_link_active(a) ((a)->list_next != NULL)

/*
 * We don't care about zaps, we just want to know about regular files?
 */
fbt::zap_lockdir:entry { self->zap = 1; }
fbt::zap_lockdir:return { self->zap = 0; }
fbt::dmu_tx_hold_sa:entry { self->hsa = 1; }
fbt::dmu_tx_hold_sa:return { self->hsa = 0; }
fbt::dmu_tx_hold_zap:entry { self->hzap = 1; }
fbt::dmu_tx_hold_zap:return { self->hzap = 0; }

fbt::dnode_hold:entry
/!self->zap && !self->hsa && !self->hzap/
{
	self->dnp = args[3];
}

fbt::dnode_hold:return
/self->dnp && (*self->dnp == NULL || arg1 != 0)/
{
	self->dnp = 0;
}

/*
 * When we return from a successful hold, check to see if the problem exists
 * before we return the dnode to the caller.
 */
fbt::dnode_hold:return
/self->dnp && arg1 == 0 && *self->dnp != NULL/
{
	this->dn = *self->dnp;

	this->dl0 = list_link_active(&this->dn->dn_dirty_link[0]);
	this->dl1 = list_link_active(&this->dn->dn_dirty_link[1]);
	this->dl2 = list_link_active(&this->dn->dn_dirty_link[2]);
	this->dl3 = list_link_active(&this->dn->dn_dirty_link[3]);
	this->dr0 = !list_empty(&this->dn->dn_dirty_records[0]);
	this->dr1 = !list_empty(&this->dn->dn_dirty_records[1]);
	this->dr2 = !list_empty(&this->dn->dn_dirty_records[2]);
	this->dr3 = !list_empty(&this->dn->dn_dirty_records[3]);

	this->dl = this->dl0 || this->dl1 || this->dl2 || this->dl3;
	this->dr = this->dr0 || this->dr1 || this->dr2 || this->dr3;

	/*
	 * We care about the case where the old and new checks do not line up,
	 * AND the new check says something is dirty:
	 */
	problem[this->dn] = this->dl != this->dr && this->dr != 0;

	self->dnp = 0;
}

/*
 * On release, check again to see if the problem exists now, before we let the
 * dnode go.
 */
fbt::dnode_rele:entry
/!self->zap && !self->hsa && !self->hzap/
{
	this->dn = args[0];

	this->dl0 = list_link_active(&this->dn->dn_dirty_link[0]);
	this->dl1 = list_link_active(&this->dn->dn_dirty_link[1]);
	this->dl2 = list_link_active(&this->dn->dn_dirty_link[2]);
	this->dl3 = list_link_active(&this->dn->dn_dirty_link[3]);
	this->dr0 = !list_empty(&this->dn->dn_dirty_records[0]);
	this->dr1 = !list_empty(&this->dn->dn_dirty_records[1]);
	this->dr2 = !list_empty(&this->dn->dn_dirty_records[2]);
	this->dr3 = !list_empty(&this->dn->dn_dirty_records[3]);

	this->dl = this->dl0 || this->dl1 || this->dl2 || this->dl3;
	this->dr = this->dr0 || this->dr1 || this->dr2 || this->dr3;

	if (!problem[this->dn] && this->dl == 0 && this->dr != 0) {
		printf("dnode %p has newly bad dirty info: ", this->dn);
		printf("%s%s%s%s %s%s%s%s\n",
		    this->dl0 ? "L" : "_",
		    this->dl1 ? "L" : "_",
		    this->dl2 ? "L" : "_",
		    this->dl3 ? "L" : "_",
		    this->dr0 ? "R" : "_",
		    this->dr1 ? "R" : "_",
		    this->dr2 ? "R" : "_",
		    this->dr3 ? "R" : "_");

		stack();
		printf("\n");
	}
}
