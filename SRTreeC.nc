#include "SimpleRoutingTree.h"
#ifdef PRINTFDBG_MODE
	#include "printf.h"
#endif

module SRTreeC
{
	uses interface Boot;
	uses interface SplitControl as RadioControl;

	uses interface Packet as RoutingPacket;
	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;
	
	uses interface AMSend as NotifyAMSend;
	uses interface AMPacket as NotifyAMPacket;
	uses interface Packet as NotifyPacket;

	uses interface Timer<TMilli> as RoutingMsgTimer;
	
	uses interface Timer<TMilli> as LostTaskTimer;
	
	uses interface Receive as RoutingReceive;
	uses interface Receive as NotifyReceive;
	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	
	uses interface PacketQueue as NotifySendQueue;
	uses interface PacketQueue as NotifyReceiveQueue;
}
implementation
{
	uint16_t  roundCounter;
	
	message_t radioRoutingSendPkt;
	message_t radioNotifySendPkt;
	
	
	message_t serialPkt;
	//message_t serialRecPkt;
	
	bool RoutingSendBusy=FALSE;
	bool NotifySendBusy=FALSE;
	
	bool lostRoutingSendTask=FALSE;
	bool lostNotifySendTask=FALSE;
	bool lostRoutingRecTask=FALSE;
	bool lostNotifyRecTask=FALSE;
	
	uint8_t curdepth;
	uint16_t parentID;
	
	task void sendRoutingTask();
	task void sendNotifyTask();
	task void receiveRoutingTask();
	task void receiveNotifyTask();
	
	void setLostRoutingSendTask(bool state)
	{
		atomic{
			lostRoutingSendTask=state;
		}
		if(state==TRUE)
		{
			//call Leds.led2On();
		}
		else 
		{
			//call Leds.led2Off();
		}
	}
	
	void setLostNotifySendTask(bool state)
	{
		atomic{
		lostNotifySendTask=state;
		}
		
		if(state==TRUE)
		{
			//call Leds.led2On();
		}
		else 
		{
			//call Leds.led2Off();
		}
	}
	
	void setLostNotifyRecTask(bool state)
	{
		atomic{
		lostNotifyRecTask=state;
		}
	}
	
	void setLostRoutingRecTask(bool state)
	{
		atomic{
		lostRoutingRecTask=state;
		}
	}
	void setRoutingSendBusy(bool state)
	{
		atomic{
		RoutingSendBusy=state;
		}
		
	}
	
	void setNotifySendBusy(bool state)
	{
		atomic{
		NotifySendBusy=state;
		}
		dbg("SRTreeC","NotifySendBusy = %s\n", (state == TRUE)?"TRUE":"FALSE");
	
	}

	event void Boot.booted()
	{
		/////// arxikopoiisi radio kai serial
		call RadioControl.start();
		
		setRoutingSendBusy(FALSE);
		setNotifySendBusy(FALSE);

		roundCounter =0;
		
		if(TOS_NODE_ID==0)
		{
			curdepth=0;
			parentID=0;
			dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
		else
		{
			curdepth=-1;
			parentID=-1;
			dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
	}
	
	event void RadioControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
			dbg("Radio" , "Radio initialized successfully!!!\n");
			
			//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
			//call RoutingMsgTimer.startPeriodic(TIMER_PERIOD_MILLI);
			//call LostTaskTimer.startPeriodic(SEND_CHECK_MILLIS);
			if (TOS_NODE_ID==0)
			{
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
			}
		}
		else
		{
			dbg("Radio" , "Radio initialization failed! Retrying...\n");
			call RadioControl.start();
		}
	}
	
	event void RadioControl.stopDone(error_t err)
	{ 
		dbg("Radio", "Radio stopped!\n");

	}

	event void LostTaskTimer.fired()
	{
		if (lostRoutingSendTask)
		{
			post sendRoutingTask();
			setLostRoutingSendTask(FALSE);
		}
		
		if( lostNotifySendTask)
		{
			post sendNotifyTask();
			setLostNotifySendTask(FALSE);
		}
		
		if (lostRoutingRecTask)
		{
			post receiveRoutingTask();
			setLostRoutingRecTask(FALSE);
		}
		
		if ( lostNotifyRecTask)
		{
			post receiveNotifyTask();
			setLostNotifyRecTask(FALSE);
		}
}

	
	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;
		dbg("SRTreeC", "RoutingMsgTimer fired!  radioBusy = %s \n",(RoutingSendBusy)?"True":"False");

		if (TOS_NODE_ID==0)
		{
			roundCounter+=1;
			
			dbg("SRTreeC", "\n ##################################### \n");
			dbg("SRTreeC", "#######   ROUND   %u    ############## \n", roundCounter);
			dbg("SRTreeC", "#####################################\n");
			
			call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
		}
		
		if(call RoutingSendQueue.full())
		{
			dbg("SRTreeC", "RoutingSendQueue is FULL!!! \n");
			return;
		}
		
		
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL)
		{
			dbg("SRTreeC","RoutingMsgTimer.fired(): No valid payload... \n");
			return;
		}
		atomic{
		mrpkt->senderID=TOS_NODE_ID;
		mrpkt->depth = curdepth;
		}
		dbg("SRTreeC" , "Sending RoutingMsg... \n");
		
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		
		enqueueDone=call RoutingSendQueue.enqueue(tmp);
		
		if( enqueueDone==SUCCESS)
		{
			if (call RoutingSendQueue.size()==1)
			{
				dbg("SRTreeC", "SendTask() posted!!\n");
				post sendRoutingTask();
			}
			
			dbg("SRTreeC","RoutingMsg enqueued successfully in SendingQueue!!!\n");
		}
		else
		{
			dbg("SRTreeC","RoutingMsg failed to be enqueued in SendingQueue!!!");
		}		
	}
	
	
	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		dbg("SRTreeC", "A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");

		
		dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");

		setRoutingSendBusy(FALSE);
		
		if(!(call RoutingSendQueue.empty()))
		{
			post sendRoutingTask();
		}
	
		
	}
	
	event void NotifyAMSend.sendDone(message_t *msg , error_t err)
	{
		dbg("SRTreeC", "A Notify package sent... %s \n",(err==SUCCESS)?"True":"False");
		
	
		dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");

		setNotifySendBusy(FALSE);
		
		if(!(call NotifySendQueue.empty()))
		{
			post sendNotifyTask();
		}
		
		
		
	}
	
	
	
	event message_t* NotifyReceive.receive( message_t* msg , void* payload , uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource = call NotifyAMPacket.source(msg);
		
		dbg("SRTreeC", "### NotifyReceive.receive() start ##### \n");
		dbg("SRTreeC", "Something received!!!  from %u   %u \n",((NotifyParentMsg*) payload)->senderID, msource);

		//if(len!=sizeof(NotifyParentMsg))
		//{
			//dbg("SRTreeC","\t\tUnknown message received!!!\n");
//#ifdef PRINTFDBG_MODE
			//printf("\t\t Unknown message received!!!\n");
			//printfflush();
//#endif
			//return msg;http://courses.ece.tuc.gr/
		//}
		
		//call Leds.led1On();
		//call Led1Timer.startOneShot(TIMER_LEDS_MILLI);
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		//tmp=*(message_t*)msg;
		}
		enqueueDone=call NotifyReceiveQueue.enqueue(tmp);
		
		if( enqueueDone== SUCCESS)
		{
			dbg("SRTreeC","posting receiveNotifyTask()!!!! \n");
			post receiveNotifyTask();
		}
		else
		{
			dbg("SRTreeC","NotifyMsg enqueue failed!!! \n");
			
		}
		
		//call Leds.led1Off();
		dbg("SRTreeC", "### NotifyReceive.receive() end ##### \n");
		return msg;
	}
//	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);
		
		dbg("SRTreeC", "### RoutingReceive.receive() start ##### \n");
		dbg("SRTreeC", "Something received!!!  from %u  %u \n",((RoutingMsg*) payload)->senderID ,  msource);
		//dbg("SRTreeC", "Something received!!!\n");
		//call Leds.led1On();
		//call Led1Timer.startOneShot(TIMER_LEDS_MILLI);
		
		//if(len!=sizeof(RoutingMsg))
		//{
			//dbg("SRTreeC","\t\tUnknown message received!!!\n");
//#ifdef PRINTFDBG_MODE
			//printf("\t\t Unknown message received!!!\n");
			//printfflush();
//#endif
			//return msg;
		//}
		
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		//tmp=*(message_t*)msg;
		}
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			dbg("SRTreeC","posting receiveRoutingTask()!!!! \n");
			post receiveRoutingTask();
		}
		else
		{
			dbg("SRTreeC","RoutingMsg enqueue failed!!! \n");			
		}
		
		//call Leds.led1Off();
		
		dbg("SRTreeC", "### RoutingReceive.receive() end ##### \n");
		return msg;
	}
	
	
	////////////// Tasks implementations //////////////////////////////
	
	
	task void sendRoutingTask()
	{
		//uint8_t skip;
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
		//message_t radioRoutingSendPkt;
		dbg("SRTreeC","SendRoutingTask(): Starting....\n");
		if (call RoutingSendQueue.empty())
		{
			dbg("SRTreeC","sendRoutingTask(): Q is empty!\n");
			return;
		}
		
		
		if(RoutingSendBusy)
		{
			dbg("SRTreeC","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			setLostRoutingSendTask(TRUE);
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue();
		
		//call Leds.led2On();
		//call Led2Timer.startOneShot(TIMER_LEDS_MILLI);
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);
		if(mlen!=sizeof(RoutingMsg))
		{
			dbg("SRTreeC","\t\tsendRoutingTask(): Unknown message!!!\n");

			return;
		}
		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("SRTreeC","sendRoutingTask(): Send returned success!!!\n");
			setRoutingSendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","send failed!!!\n");

			//setRoutingSendBusy(FALSE);
		}
	}
	/**
	 * dequeues a message and sends it
	 */
	task void sendNotifyTask()
	{
		uint8_t mlen;//, skip;
		error_t sendDone;
		uint16_t mdest;
		NotifyParentMsg* mpayload;
		
		//message_t radioNotifySendPkt;
		dbg("SRTreeC","SendNotifyTask(): going to send one more package.\n");

		if (call NotifySendQueue.empty())
		{
			dbg("SRTreeC","sendNotifyTask(): Q is empty!\n");
			return;
		}
		
		if(NotifySendBusy==TRUE)
		{
			dbg("SRTreeC","sendNotifyTask(): NotifySendBusy= TRUE!!!\n");

			setLostNotifySendTask(TRUE);
			return;
		}
		
		radioNotifySendPkt = call NotifySendQueue.dequeue();
		
		//call Leds.led2On();
		//call Led2Timer.startOneShot(TIMER_LEDS_MILLI);
		mlen=call NotifyPacket.payloadLength(&radioNotifySendPkt);
		
		mpayload= call NotifyPacket.getPayload(&radioNotifySendPkt,mlen);
		
		if(mlen!= sizeof(NotifyParentMsg))
		{
			dbg("SRTreeC", "\t\t sendNotifyTask(): Unknown message!!\n");
			return;
		}
		
		dbg("SRTreeC" , " sendNotifyTask(): mlen = %u  senderID= %u \n",mlen,mpayload->senderID);

		mdest= call NotifyAMPacket.destination(&radioNotifySendPkt);
		
		
		sendDone=call NotifyAMSend.send(mdest,&radioNotifySendPkt, mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("SRTreeC","sendNotifyTask(): Send returned success!!!\n");

			setNotifySendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","send failed!!!\n");

			//setNotifySendBusy(FALSE);
		}
	}
	////////////////////////////////////////////////////////////////////
	//*****************************************************************/
	///////////////////////////////////////////////////////////////////
	/**
	 * dequeues a message and processes it
	 */
	
	task void receiveRoutingTask()
	{
		message_t tmp;
		uint8_t len;
		message_t radioRoutingRecPkt;
		
		dbg("SRTreeC","ReceiveRoutingTask():received msg...\n");

		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue();
		
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		
		dbg("SRTreeC","ReceiveRoutingTask(): len=%u \n",len);

		// processing of radioRecPkt
		
		// pos tha xexorizo ta 2 diaforetika minimata???
				
		if(len == sizeof(RoutingMsg))
		{
			NotifyParentMsg* m;
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));
			
			//if(TOS_NODE_ID >0)
			//{
				//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
			//}
			//
			dbg("NodeID= %d , RoutingMsg received! \n",TOS_NODE_ID);
			dbg("SRTreeC" , "receiveRoutingTask():senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);

			if ( (parentID<0)||(parentID>=65535))
			{
				// tote den exei akoma patera
				parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;q
				curdepth= mpkt->depth + 1;
				dbg("NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);

				// tha stelnei kai ena minima NotifyParentMsg ston patera
				
				m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
				m->senderID=TOS_NODE_ID;
				m->depth = curdepth;
				m->parentID = parentID;
				dbg("SRTreeC" , "receiveRoutingTask():NotifyParentMsg sending to node= %d... \n", parentID);

				call NotifyAMPacket.setDestination(&tmp, parentID);
				call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
				
				if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
				{
					dbg("SRTreeC", "receiveRoutingTask(): NotifyParentMsg enqueued in SendingQueue successfully!!!");

					if (call NotifySendQueue.size() == 1)
					{
						post sendNotifyTask();
					}
				}
				if (TOS_NODE_ID!=0)
				{
					call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
				}
			}
			else
			{
				
				if (( curdepth > mpkt->depth +1) || (mpkt->senderID==parentID))
				{
					uint16_t oldparentID = parentID;
					
				
					parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;
					curdepth = mpkt->depth + 1;
					dbg("SRTreeC" , "NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);				
									
					
					dbg("SRTreeC" , "NotifyParentMsg sending to node= %d... \n", oldparentID);

					if ( (oldparentID<65535) || (oldparentID>0) || (oldparentID==parentID))
					{
						m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
						m->senderID=TOS_NODE_ID;
						m->depth = curdepth;
						m->parentID = parentID;
						
						call NotifyAMPacket.setDestination(&tmp,oldparentID);
						//call NotifyAMPacket.setType(&tmp,AM_NOTIFYPARENTMSG);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
								
						if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
						{
							dbg("SRTreeC", "receiveRoutingTask(): NotifyParentMsg enqueued in SendingQueue successfully!!!\n");

							if (call NotifySendQueue.size() == 1)
							{
								post sendNotifyTask();
							}
						}
					}
					if (TOS_NODE_ID!=0)
					{
						call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
					}
					// tha stelnei kai ena minima NotifyParentMsg 
					// ston kainourio patera kai ston palio patera.
					
					if (oldparentID!=parentID)
					{
						m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
						m->senderID=TOS_NODE_ID;
						m->depth = curdepth;
						m->parentID = parentID;
						dbg("SRTreeC" , "receiveRoutingTask():NotifyParentMsg sending to node= %d... \n", parentID);

						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
						
						if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
						{
							dbg("SRTreeC", "receiveRoutingTask(): NotifyParentMsg enqueued in SendingQueue successfully!!! \n");

							if (call NotifySendQueue.size() == 1)
							{
								post sendNotifyTask();
							}
						}
					}
				}
				
				
			}
		}
		else
		{
			dbg("SRTreeC","receiveRoutingTask():Empty message!!! \n");

			setLostRoutingRecTask(TRUE);
			return;
		}
		
	}


////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////	
	
	 
	task void receiveNotifyTask()
	{
		message_t tmp;
		uint8_t len;
		message_t radioNotifyRecPkt;
		
		dbg("SRTreeC","ReceiveNotifyTask():received msg...\n");

		radioNotifyRecPkt= call NotifyReceiveQueue.dequeue();
		
		len= call NotifyPacket.payloadLength(&radioNotifyRecPkt);
		
		dbg("SRTreeC","ReceiveNotifyTask(): len=%u \n",len);

		if(len == sizeof(NotifyParentMsg))
		{
			// an to parentID== TOS_NODE_ID tote
			// tha proothei to minima pros tin riza xoris broadcast
			// kai tha ananeonei ton tyxon pinaka paidion..
			// allios tha diagrafei to paidi apo ton pinaka paidion
			
			NotifyParentMsg* mr = (NotifyParentMsg*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
			
			dbg("SRTreeC" , "NotifyParentMsg received from %d !!! \n", mr->senderID);

			if ( mr->parentID == TOS_NODE_ID)
			{
				// tote prosthiki stin lista ton paidion.
				
			}
			else
			{
				// apla diagrafei ton komvo apo paidi tou..
				
			}
			if ( TOS_NODE_ID==0)
			{
// #ifdef SERIAL_EN
// 				if (!serialBusy)
// 				{ // mipos mporei na mpei san task?
// 					NotifyParentMsg * m = (NotifyParentMsg *) (call SerialPacket.getPayload(&serialPkt, sizeof(NotifyParentMsg)));
// 					m->senderID=mr->senderID;
// 					m->depth = mr->depth;
// 					m->parentID = mr->parentID;
// 					dbg("Serial", "Sending NotifyParentMsg to PC... \n");
// #ifdef PRINTFDBG_MODE
// 					printf("Sending NotifyParentMsg to PC..\n");
// 					printfflush();
// #endif
// 					if (call SerialAMSend.send(parentID, &serialPkt, sizeof(NotifyParentMsg))==SUCCESS)
// 					{
// 						setSerialBusy(TRUE);
// 					}
// 				}
// #endif
			}
			else
			{
				NotifyParentMsg* m;
				memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
				
				m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
				//m->senderID=mr->senderID;
				//m->depth = mr->depth;
				//m->parentID = mr->parentID;
				
				dbg("SRTreeC" , "Forwarding NotifyParentMsg from senderID= %d  to parentID=%d \n" , m->senderID, parentID);

				call NotifyAMPacket.setDestination(&tmp, parentID);
				call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
				
				if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
				{
					dbg("SRTreeC", "receiveNotifyTask(): NotifyParentMsg enqueued in SendingQueue successfully!!!\n");
					if (call NotifySendQueue.size() == 1)
					{
						post sendNotifyTask();
					}
				}

				
			}
			
		}
		else
		{
			dbg("SRTreeC","receiveNotifyTask():Empty message!!! \n");
			setLostNotifyRecTask(TRUE);
			return;
		}
		
	}
	
}
