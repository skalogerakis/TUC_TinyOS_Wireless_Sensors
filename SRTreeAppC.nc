#include "SimpleRoutingTree.h"

configuration SRTreeAppC @safe() { }
implementation{
	components SRTreeC;

#if defined(DELUGE) //defined(DELUGE_BASESTATION) || defined(DELUGE_LIGHT_BASESTATION)
	components DelugeC;
#endif

#ifdef PRINTFDBG_MODE
		components PrintfC;
#endif
	components MainC, ActiveMessageC;
	components new TimerMilliC() as RoutingMsgTimerC;
	components new TimerMilliC() as RoutingComplTimerC;
	components new TimerMilliC() as LostTaskTimerC;
	components new TimerMilliC() as DistrMsgTimerC;
	
	components new AMSenderC(AM_ROUTINGMSG) as RoutingSenderC;
	components new AMReceiverC(AM_ROUTINGMSG) as RoutingReceiverC;
	components new AMSenderC(AM_NOTIFYPARENTMSG) as NotifySenderC;
	components new AMReceiverC(AM_NOTIFYPARENTMSG) as NotifyReceiverC;

	//KP Edit
	//TODO fix struct
	components new AMSenderC(AM_NOTIFYPARENTMSG) as DistrSenderC;
	components new AMReceiverC(AM_NOTIFYPARENTMSG) as DistrReceiverC;
	components new PacketQueueC(SENDER_QUEUE_SIZE) as DistrSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as DistrReceiveQueueC;


	components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;
	components new PacketQueueC(SENDER_QUEUE_SIZE) as NotifySendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as NotifyReceiveQueueC;
	
	SRTreeC.Boot->MainC.Boot;
	
	SRTreeC.RadioControl -> ActiveMessageC;
	
	SRTreeC.RoutingMsgTimer->RoutingMsgTimerC;
	SRTreeC.DistrMsgTimer->DistrMsgTimerC;
	SRTreeC.RoutingComplTimer->RoutingComplTimerC;
	SRTreeC.LostTaskTimer->LostTaskTimerC;
	
	SRTreeC.RoutingPacket->RoutingSenderC.Packet;
	SRTreeC.RoutingAMPacket->RoutingSenderC.AMPacket;
	SRTreeC.RoutingAMSend->RoutingSenderC.AMSend;
	SRTreeC.RoutingReceive->RoutingReceiverC.Receive;

	//KP Edit
	SRTreeC.DistrPacket->DistrSenderC.Packet;
	SRTreeC.DistrAMPacket->DistrSenderC.AMPacket;
	SRTreeC.DistrAMSend->DistrSenderC.AMSend;
	SRTreeC.DistrReceive->DistrReceiverC.Receive;
	
	SRTreeC.NotifyPacket->NotifySenderC.Packet;
	SRTreeC.NotifyAMPacket->NotifySenderC.AMPacket;
	SRTreeC.NotifyAMSend->NotifySenderC.AMSend;
	SRTreeC.NotifyReceive->NotifyReceiverC.Receive;
	
	SRTreeC.RoutingSendQueue->RoutingSendQueueC;
	SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;
	SRTreeC.NotifySendQueue->NotifySendQueueC;
	SRTreeC.NotifyReceiveQueue->NotifyReceiveQueueC;
	
}
