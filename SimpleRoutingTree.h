#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H


enum{
	SENDER_QUEUE_SIZE=5,
	RECEIVER_QUEUE_SIZE=3,
	AM_SIMPLEROUTINGTREEMSG=22,

	//TODO check THAT
	//KP Edit
	AM_DISTRMSG=30,
	AM_ROUTINGMSG=22,
	AM_NOTIFYPARENTMSG=12,
	SEND_CHECK_MILLIS=70000,
	TIMER_PERIOD_MILLI=150000,
	TIMER_FAST_PERIOD=200,
	TIMER_LEDS_MILLI=1000,

	EPOCH = 60000,
	MAX_CHILDREN = 20,
	MAX_DEPTH = 10,
};
/*uint16_t AM_ROUTINGMSG=AM_SIMPLEROUTINGTREEMSG;
uint16_t AM_NOTIFYPARENTMSG=AM_SIMPLEROUTINGTREEMSG;
*/
typedef nx_struct RoutingMsg
{
	nx_uint16_t senderID;
	nx_uint8_t depth;
} RoutingMsg;

// typedef nx_struct NotifyParentMsg
// {
// 	nx_uint16_t senderID;
// 	nx_uint16_t parentID;
// 	nx_uint8_t depth;
// } NotifyParentMsg;

//TODO check optimization
typedef nx_struct DistrMsg{
	nx_uint16_t count;
	nx_uint16_t sum;
	nx_uint16_t max;
} DistrMsg;

/**Initially tried to create multiple arrays in SRTreeC.nc for each element
Better this way less memory is consumed*/
typedef nx_struct ChildDistrMsg{
	//nx_uint16_t parentID;
	nx_uint16_t senderID;
	nx_uint16_t count;
	nx_uint16_t sum;
	nx_uint16_t max;
} ChildDistrMsg;

#endif
