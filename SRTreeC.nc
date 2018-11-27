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
	

	uses interface Timer<TMilli> as RoutingMsgTimer;
	uses interface Timer<TMilli> as RoutingComplTimer;
	uses interface Timer<TMilli> as DistrMsgTimer;
	uses interface Timer<TMilli> as LostTaskTimer;
	
	uses interface Receive as RoutingReceive;
	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;

	//KP edit
	uses interface Packet as DistrPacket;
	uses interface AMSend as DistrAMSend;
	uses interface AMPacket as DistrAMPacket;

	uses interface PacketQueue as DistrSendQueue;
	uses interface PacketQueue as DistrReceiveQueue;
	uses interface Receive as DistrReceive;

	uses interface Random as RandomGen;
	uses interface ParameterInit<uint16_t> as Seed;

}
implementation
{
	uint16_t  roundCounter;
	
	message_t radioRoutingSendPkt;
	//KP Edit
	message_t radioDistrSendPkt;
	
	message_t serialPkt;
	
	bool RoutingSendBusy=FALSE;
	
	bool lostRoutingSendTask=FALSE;
	bool lostRoutingRecTask=FALSE;
	
	uint8_t curdepth;
	uint16_t parentID;
	uint8_t i;
	uint16_t startPer;

	uint16_t slotTime;
	uint16_t subSlotTime;

	//KP Edit
	/** Create Array of type ChildDristrMsg*/
	ChildDistrMsg childrenArray[MAX_CHILDREN];
	
	task void sendRoutingTask();
	task void receiveRoutingTask();
	task void sendDistrTask();
	task void receiveDistrTask();
	
	void setLostRoutingSendTask(bool state)
	{
		atomic{
			lostRoutingSendTask=state;
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

	/**Initialize children array with default values. Don't initialize max field because we don't know how the nodes are used and the max/min value*/
	void InitChildrenArray()
	{
		//uint8_t i;
		for(i=0; i< MAX_CHILDREN; i++){
			childrenArray[i].senderID = 0;
			childrenArray[i].sum = 0;
			childrenArray[i].count = 0;
		}
		
	}

	void rootMsgPrint(DistrMsg* mrpkt){
		dbg("SRTreeC", "#### Output: \n");
		dbg("SRTreeC", "#### [count] = %d\n", mrpkt->count);
		dbg("SRTreeC", "#### [sum] = %d\n", mrpkt->sum);
		dbg("SRTreeC", "#### [max] = %d\n", mrpkt->max);
		dbg("SRTreeC", "#### [AVG] = %f\n\n\n", (double)mrpkt->sum / mrpkt->count);
		//dbg("SRTreeC", "Output: [count] = %d, [sum] = %d, [max] = %d, [avg] = %f\n", mrpkt->count, mrpkt->sum, mrpkt->max, (double)mrpkt->sum / mrpkt->count);

	}

	uint8_t maxFinder(uint16_t a, uint16_t b){
		return (a > b) ? a : b;
	}
	

	event void Boot.booted()
	{
		call RadioControl.start();
		
		setRoutingSendBusy(FALSE);

		roundCounter =0;
		
		if(TOS_NODE_ID==0)
		{
			curdepth=0;
			parentID=0;
			//dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
		else
		{
			curdepth=-1;
			parentID=-1;
			//dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}

		/**
			It is advised to pass as init parameter the different TOS_NODE_ID
			to generate different numbers at every node, as rand is pseudo random
			and does't always produce random values
		*/
		call Seed.init(TOS_NODE_ID);
	}
	
	event void RadioControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
			//dbg("Radio" , "Radio initialized successfully!!!\n");
			
			/**In case the radio was activated successfully then initialize children array */
			InitChildrenArray();

			call RoutingComplTimer.startOneShot(5000);
			
			/** Routing happens once at the start*/
			if (TOS_NODE_ID==0)
			{
				dbg("SRTreeC", "###########START ROUTING###############\n\n");
				
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
		
			}
		}
		else
		{
			//dbg("Radio" , "Radio initialization failed! Retrying...\n");
			call RadioControl.start();
		}
	}
	
	event void RadioControl.stopDone(error_t err)
	{ 
		dbg("Radio", "Radio stopped!\n");

	}

	event void RoutingComplTimer.fired(){

		slotTime = EPOCH/MAX_DEPTH;
		subSlotTime = MAX_DEPTH - curdepth;	/** WAS USED IN PREVIOUS IMPLEMENTATION WITH TIMERS*/

		//dbg("SRTreeC" , "Finished Rounting in cur node\n");
		//dbg("SRTreeC", " CHECK DEPTH INTI %d\n",curdepth);


		/** 
			Synchronize timers. Divide first the epoch in 
			slots as defined by TAG, based on max depth.Then,
			devide every slot in sub-slots based again on max_depth
			and current depth and use TOS_NODE_ID to avoid collision
			between messages. *8 was used after externsive testing.
			Also tried to multiply with random value but was not 
			effective in some cases.
		*/

		//startPer = slotTime * subSlotTime + TOS_NODE_ID * 8;


		/**
			Altered synchronization. The previous version would lose
			1 epoch due to delayed start. The method is similar with the
			previous implementation with the difference that we use sub slot
			upper bound so that we will not lose any time
		*/

		startPer =  slotTime - (curdepth*slotTime)/MAX_DEPTH + (TOS_NODE_ID * 8) ; //WORKS

		call DistrMsgTimer.startPeriodicAt(startPer, EPOCH);
	}

	event void LostTaskTimer.fired()
	{
		if (lostRoutingSendTask)
		{
			post sendRoutingTask();
			setLostRoutingSendTask(FALSE);
		}
		
		
		if (lostRoutingRecTask)
		{
			post receiveRoutingTask();
			setLostRoutingRecTask(FALSE);
		}
		
}

	
	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;
		//dbg("SRTreeC", "RoutingMsgTimer fired!  radioBusy = %s \n",(RoutingSendBusy)?"True":"False");

		if(call RoutingSendQueue.full())
		{
			//dbg("SRTreeC", "RoutingSendQueue is FULL!!! \n");
			return;
		}
		
		
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL)
		{
			//dbg("SRTreeC","RoutingMsgTimer.fired(): No valid payload... \n");
			return;
		}
		atomic{
		mrpkt->senderID=TOS_NODE_ID;
		mrpkt->depth = curdepth;
		}

		//dbg("SRTreeC" , "Sending RoutingMsg... \n");
		
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		
		enqueueDone=call RoutingSendQueue.enqueue(tmp);
		
		if( enqueueDone==SUCCESS)
		{
			if (call RoutingSendQueue.size()==1)
			{
				//dbg("SRTreeC", "SendTask() posted!!\n");
				post sendRoutingTask();
			}
			
			//dbg("SRTreeC","RoutingMsg enqueued successfully in SendingQueue!!!\n");
		}
		else
		{
			//dbg("SRTreeC","RoutingMsg failed to be enqueued in SendingQueue!!!");
		}		
	}

	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		//dbg("SRTreeC", "A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");

		
		//dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");

		setRoutingSendBusy(FALSE);
		
		if(!(call RoutingSendQueue.empty()))
		{
			//dbg("SRTreeC" , "Check what this does!!!!");
			post sendRoutingTask();
		}
	
		
	}

	//based on RoutingMsgTimer
	event void DistrMsgTimer.fired()
	{
		

		message_t tmp;
		error_t enqueueDone;
		uint16_t randVal;

		DistrMsg* mrpkt;

		
		if(call DistrSendQueue.full())
		{
			//dbg("SRTreeC", "DistrSendQueue is FULL!!! \n");
			return;
		}
		
		
		mrpkt = (DistrMsg*) (call DistrPacket.getPayload(&tmp, sizeof(DistrMsg)));

		if(mrpkt==NULL)
		{
			//dbg("SRTreeC","DistrMsgTimer.fired(): No valid payload... \n");
			return;
		}


		/** Random value generator.
			Already initialized and produces random values from 0 to 50
		*/
		randVal = call RandomGen.rand16() % 50;

		dbg("SRTreeC", "Random value generated %d\n", randVal);

		atomic{
		mrpkt->sum = randVal;
		mrpkt->count = 1;
		mrpkt->max = randVal;


		//SINATHRISI ASSIGN TO
		for(i = 0 ;i < MAX_CHILDREN && childrenArray[i].senderID!=0 ; i++){
			mrpkt->count += childrenArray[i].count;
			mrpkt->sum += childrenArray[i].sum;
			mrpkt->max = maxFinder(childrenArray[i].max, mrpkt->max);
		}

		//mrpkt->senderID = TOS_NODE_ID;

		}


	
		/** root case print everything*/
		if(TOS_NODE_ID == 0){
			roundCounter+=1;

			dbg("SRTreeC", "\n\n########################Epoch %d completed#####################\n", roundCounter);
			rootMsgPrint(mrpkt);
			//dbg("SRTreeC", "Output: [count] = %d, [sum] = %d, [max] = %d, [avg] = %f\n", mrpkt->count, mrpkt->sum, mrpkt->max, (double)mrpkt->sum / mrpkt->count);
		}
		else /** case we don't have root node then sent everything to the parent*/
		{

			dbg("SRTreeC", "Node: %d , Parent: %d, Sum: %d, count: %d, max: %d , depth: %d\n",TOS_NODE_ID,parentID, mrpkt->sum, mrpkt->count, mrpkt->max, curdepth);
			call DistrAMPacket.setDestination(&tmp, parentID);
			call DistrPacket.setPayloadLength(&tmp, sizeof(DistrMsg));

			enqueueDone=call DistrSendQueue.enqueue(tmp);

			if( enqueueDone==SUCCESS)
			{
				if (call DistrSendQueue.size()==1)
				{
					//dbg("SRTreeC", "SendDistrTask() posted!!\n");
					post sendDistrTask();
				}
			
				//dbg("SRTreeC","DistrMsg enqueued successfully in SendingQueue!!!\n");
			}
			else
			{
				dbg("SRTreeC","DistrMsg failed to be enqueued in SendingQueue!!!");
			}

		}		
	}


	event void DistrAMSend.sendDone(message_t * msg , error_t err)
	{
		//dbg("SRTreeC", "A Distribution package sent... %s \n",(err==SUCCESS)?"True":"False");

		//setRoutingSendBusy(FALSE);
		//TODO CHECK STATEMENT BELOW. THEORITICALY IT SHOULD WORK
		// if(!(call RoutingSendQueue.empty()))
		// {
		// 	post sendDistrTask();
		// }
	
		
	}

	event message_t* DistrReceive.receive( message_t* msg , void* payload , uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource = call DistrAMPacket.source(msg);
		
		//dbg("SRTreeC", "### DistrReceive.receive() start ##### \n");
		
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		//tmp=*(message_t*)msg;
		}
		enqueueDone=call DistrReceiveQueue.enqueue(tmp);
		
		if( enqueueDone== SUCCESS)
		{
			//dbg("SRTreeC","posting receiveDistrTask()!!!! \n");
			post receiveDistrTask();
		}
		else
		{
			dbg("SRTreeC","DistrMsg enqueue failed!!! \n");
			
		}
		
		//dbg("SRTreeC", "### DistrReceive.receive() end ##### \n");
		return msg;
	}
	
	
	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);
		
		//dbg("SRTreeC", "### RoutingReceive.receive() start ##### \n");
		//dbg("SRTreeC", "Something received!!!  from %u  %u \n",((RoutingMsg*) payload)->senderID ,  msource);
		
		
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		}
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			//dbg("SRTreeC","posting receiveRoutingTask()!!!! \n");
			post receiveRoutingTask();
		}
		else
		{
			dbg("SRTreeC","RoutingMsg enqueue failed!!! \n");			
		}
		
		//call Leds.led1Off();
		
		//dbg("SRTreeC", "### RoutingReceive.receive() end ##### \n");
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
		//dbg("SRTreeC","SendRoutingTask(): Starting....\n");
		if (call RoutingSendQueue.empty())
		{
			//dbg("SRTreeC","sendRoutingTask(): Q is empty!\n");
			return;
		}
		
		
		if(RoutingSendBusy)
		{
			//dbg("SRTreeC","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			setLostRoutingSendTask(TRUE);
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue();
		
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);

		if(mlen!=sizeof(RoutingMsg))
		{
			//dbg("SRTreeC","\t\tsendRoutingTask(): Unknown message!!!\n");

			return;
		}
		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);
		
		if ( sendDone== SUCCESS)
		{
			//dbg("SRTreeC","sendRoutingTask(): Send returned success!!!\n");
			setRoutingSendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","send failed!!!\n");

			//setRoutingSendBusy(FALSE);
		}
	}
	

	task void sendDistrTask()
	{
		uint8_t mlen;//, skip;
		error_t sendDone;
		uint16_t mdest;
		DistrMsg* mpayload;
		
		//dbg("SRTreeC","SendDistrTask(): going to send one more package.\n");

		if (call DistrSendQueue.empty())
		{
			//dbg("SRTreeC","sendDistrTask(): Q is empty!\n");
			return;
		}
		
		//TODO create that
		// if(NotifySendBusy==TRUE)
		// {
		// 	dbg("SRTreeC","sendNotifyTask(): NotifySendBusy= TRUE!!!\n");

		// 	setLostNotifySendTask(TRUE);
		// 	return;
		// }
		
		radioDistrSendPkt = call DistrSendQueue.dequeue();
		mlen=call DistrPacket.payloadLength(&radioDistrSendPkt);
		mpayload= call DistrPacket.getPayload(&radioDistrSendPkt,mlen);
		
		if(mlen!= sizeof(DistrMsg))
		{
			//dbg("SRTreeC", "\t\t sendDistrTask(): Unknown message!!\n");
			return;
		}
		
		//TODO check that
		//dbg("SRTreeC" , " sendDistrTask(): mlen = %u  senderID= %u \n",mlen,mpayload->senderID);

		mdest= call DistrAMPacket.destination(&radioDistrSendPkt);
		
		
		sendDone=call DistrAMSend.send(mdest,&radioDistrSendPkt, mlen);
		
		if ( sendDone== SUCCESS)
		{
			//dbg("SRTreeC","sendDistrTask(): Send returned success!!!\n");

			//setNotifySendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","sendDistrTask(): Send returned failed!!!\n");

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
		
		//dbg("SRTreeC","ReceiveRoutingTask():received msg...\n");

		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue();
		
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		
		//dbg("SRTreeC","ReceiveRoutingTask(): len=%u \n",len);

		// processing of radioRecPkt
		
		// pos tha xexorizo ta 2 diaforetika minimata???
				
		if(len == sizeof(RoutingMsg))
		{
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));
			
			//dbg("SRTreeC" ,"NodeID= %d , RoutingMsg received! \n",TOS_NODE_ID);
			//dbg("SRTreeC" , "receiveRoutingTask():senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);

			/**In that case we don't have a father yet*/
			if ( (parentID<0)||(parentID>=65535))
			{

				parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;q
				curdepth= mpkt->depth + 1;
				// dbg("SRTreeC" ,"NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);

		
				if (TOS_NODE_ID!=0)
				{
					dbg("SRTreeC" ,"NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
					call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
				}
			}
			/** We already have a parent and we don't need to find
				a better parent to implement TAG as requested. So just print
				a message in that case
			*/
			else
			{
			 	//dbg("SRTreeC" ,"Already have a parent with NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
			}
			
		}
		else
		{
			//dbg("SRTreeC","receiveRoutingTask():Empty message!!! \n");

			setLostRoutingRecTask(TRUE);
			return;
		}
		
	}


	/** Based on receiveNotifyTask()*/
	task void receiveDistrTask()
	{
		message_t tmp;
		uint8_t len;
		uint8_t source;
		message_t radioDistrRecPkt;
		
		//dbg("SRTreeC","ReceiveDistrTask():received msg...\n");

		radioDistrRecPkt= call DistrReceiveQueue.dequeue();
		
		len= call DistrPacket.payloadLength(&radioDistrRecPkt);

		//TODO check that
		source = call DistrAMPacket.source(&radioDistrRecPkt);
		
		//dbg("SRTreeC","ReceiveDistrTask(): len=%u \n",len);

		if(len == sizeof(DistrMsg))
		{
			// an to parentID== TOS_NODE_ID tote
			// tha proothei to minima pros tin riza xoris broadcast
			// kai tha ananeonei ton tyxon pinaka paidion..
			// allios tha diagrafei to paidi apo ton pinaka paidion
			
			DistrMsg* mr = (DistrMsg*) (call DistrPacket.getPayload(&radioDistrRecPkt,len));
			//uint8_t i
			for(i=0; i< MAX_CHILDREN ; i++){
				if(source == childrenArray[i].senderID || childrenArray[i].senderID == 0){
					childrenArray[i].senderID = source;
					childrenArray[i].count = mr->count;
					childrenArray[i].sum = mr->sum;
					childrenArray[i].max = mr->max;
					break;

				}else{
					/**
						Still haven't found from the children array the right
						destination
					*/
					//dbg("SRTreeC","CHECK IT %d \n",childrenArray[i].senderID);
					//dbg("SRTreeC", "#############SOMETHING........");
				}
			}
			
		}
		else
		{
			//dbg("SRTreeC","receiveDistrTask():Empty message!!! \n");
			//setLostNotifyRecTask(TRUE);
			return;
		}
		
	}
	 
	
}
