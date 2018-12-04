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
	TCT = 80,
	PERCENTAGE = 100,

	EPOCH = 60000,
	MAX_CHILDREN = 20,
	MAX_DEPTH = 14,
};

typedef nx_struct RoutingMsg
{
	nx_uint16_t ques;
	nx_uint16_t senderID;
	nx_uint8_t depth;
} RoutingMsg;

typedef nx_struct DistrMsg{
	nx_uint16_t count;
	nx_uint16_t sum;
	nx_uint16_t max;
} DistrMsg;


/**
	Created the most abstract structs to generalize the problem.
	Our main issue was to minimize the messages send. The most
	messages demanded are when variance and max/min are combined(4 fields).
	The least is in the case where only one message is sent. In every case,
	i must explain in comments where each field is refered.
*/
typedef nx_struct DistrMsg4{
	nx_uint16_t field4a;
	nx_uint16_t field4b;
	nx_uint16_t field4c;
	nx_uint16_t field4d;
} DistrMsg4;

typedef nx_struct DistrMsg3{
	nx_uint16_t field3a;
	nx_uint16_t field3b;
	nx_uint16_t field3c;
} DistrMsg3;

typedef nx_struct DistrMsg2{
	nx_uint16_t field2a;
	nx_uint16_t field2b;
} DistrMsg2;

typedef nx_struct DistrMsg1{
	nx_uint16_t field1a;
} DistrMsg1;

typedef nx_struct DistrMsgOpt{
	DistrMsg1 msg1;
	DistrMsg2 msg2;
	DistrMsg3 msg3;
	DistrMsg4 msg4;
} DistrMsgOpt;


/**Initially tried to create multiple arrays in SRTreeC.nc for each element
Better this way less memory is consumed*/
typedef nx_struct ChildDistrMsg{
	//nx_uint16_t parentID;
	nx_uint16_t senderID;
	nx_uint8_t count;
	nx_uint16_t sum;
	nx_uint8_t max;
	nx_uint8_t min;
	nx_uint16_t sumofSquares;
} ChildDistrMsg;

//double TCT = 0.8;

uint8_t numMsgSent;


uint8_t numFun=1;
uint8_t chooseFun1=1;
uint8_t chooseFun2=1;
uint8_t chooseFun=1;
uint8_t chooseProg=1;
uint8_t oldFlag = 0;

#endif
