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

	/*
	Used for random number generation
	Source: https://www.mail-archive.com/tinyos-help@millennium.berkeley.edu/msg44832.html?fbclid=IwAR0K7Iv1I1n8LtKw2ta6OfZpp9wQHSgyPF0bijCSmrY6eACocjkximcfIaI
	*/
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
	bool DistrSendBusy = FALSE;
	
	//KP EDIT
	/**Variables used*/
	uint8_t curdepth;
	uint16_t parentID;
	uint8_t i;
	uint16_t startPer;

	uint16_t slotTime;
	uint16_t subSlotSplit;
	uint16_t subSlotChoose;
	uint16_t timerCounter;


	//KP Edit
	/** Create Array of type ChildDristrMsg*/
	ChildDistrMsg childrenArray[MAX_CHILDREN];
	
	task void sendRoutingTask();
	task void receiveRoutingTask();
	task void sendDistrTask();
	task void receiveDistrTask();
	
	void setRoutingSendBusy(bool state)
	{
		atomic{
			RoutingSendBusy=state;
		}
		
	 }

	 void setDistrSendBusy(bool state){
	 	atomic{
	 		DistrSendBusy = state;
	 	}
	 }

	/**Initialize children array with default values. Don't initialize max field because we don't know how the nodes are used and the max/min value*/
	void InitChildrenArray()
	{
		for(i=0; i< MAX_CHILDREN; i++){
			childrenArray[i].senderID = 0;
			childrenArray[i].sum = 0;
			childrenArray[i].count = 0;
		}
		
	}

	/**Used to print all needed messages when we reach root*/
	void rootMsgPrint(DistrMsg* mrpkt){
		dbg("SRTreeC", "#### OUTPUT: \n");
		dbg("SRTreeC", "#### [COUNT] = %d\n", mrpkt->count);
		dbg("SRTreeC", "#### [SUM] = %d\n", mrpkt->sum);
		dbg("SRTreeC", "#### [MAX] = %d\n", mrpkt->max);
		dbg("SRTreeC", "#### [AVG] = %f\n\n\n", (double)mrpkt->sum / mrpkt->count);
	}

	/**This function returns max*/
	uint8_t maxFinder(uint16_t a, uint16_t b){
		return (a > b) ? a : b;
	}
	

	/**This is where everything starts*/
	event void Boot.booted()
	{
		call RadioControl.start();
		
		setRoutingSendBusy(FALSE);
		setDistrSendBusy(FALSE);

		roundCounter =0;
		
		if(TOS_NODE_ID==0)
		{
			curdepth=0;
			parentID=0;
		}
		else
		{
			curdepth=-1;
			parentID=-1;
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
			call RadioControl.start();
		}
	}
	
	/**In simulation mode, the radio will be successfuly booted
	but don't delete that event for plentitude*/
	event void RadioControl.stopDone(error_t err)
	{ 
		dbg("Radio", "Radio stopped!\n");

	}

	/*
		When this event is fired, it means that 5 sec available for routing
		are over and all nodes are ready to start aggregation from one level to another
	*/
	event void RoutingComplTimer.fired(){

		
		slotTime = EPOCH/(MAX_DEPTH+1);
		subSlotSplit = (MAX_DEPTH);

		subSlotChoose = (MAX_DEPTH - curdepth);


		/** 
			Synchronize timers. Divide first the epoch in 
			slots as defined by TAG, based on max depth.Then,
			devide every slot in sub-slots based again on max_depth
			and current depth and use TOS_NODE_ID to avoid collision
			between messages. *25 was used after externsive testing.
			Also tried to multiply with random value but was not 
			effective in some cases.
		*/


		/**
			Altered synchronization. The previous version would lose
			1 epoch due to time constraints and had issues when max_depth = curdepth. 
			What changed is that we added 1 extra slot and subslot at each epoch so that we are
			done before the time elapses.
		*/

		/*
			The epoch time has delay at the beginning as starting time is defined by max depth and 
			curdepth. Now maxdepth is considered to be 14. In some cases for smaller topology files
			we could assign max depth to a smaller value ex. 4. But even in that case the time that is 
			"wasted" at the beginning is compensated and all 15 epochs run as requested.
		*/

		startPer =  (slotTime / subSlotSplit * subSlotChoose) + TOS_NODE_ID * 25;


		//dbg("SRTreeC", "START %d\n", startPer);

		call DistrMsgTimer.startPeriodicAt(startPer, EPOCH);
	}

	
	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;
		

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

		
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		
		enqueueDone=call RoutingSendQueue.enqueue(tmp);
		
		if( enqueueDone==SUCCESS)
		{
			if (call RoutingSendQueue.size()==1)
			{
				post sendRoutingTask();
			}
			
		}
		else
		{
			dbg("SRTreeC","RoutingMsg failed to be enqueued in SendingQueue!!!");
		}		
	}

	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		/**
			When send a message stop trying send messages
		*/
		setRoutingSendBusy(FALSE);
		
		
	}

	//based on RoutingMsgTimer
	event void DistrMsgTimer.fired()
	{
		

		message_t tmp;
		error_t enqueueDone;
		uint16_t randVal;

		DistrMsg* mrpkt;

		/**The simulation never reaches the statements below but will not be deleted
		for plentitude*/
		if(call DistrSendQueue.full())
		{
			dbg("SRTreeC", "DistrSendQueue is FULL!!! \n");
			return;
		}
		
		
		mrpkt = (DistrMsg*) (call DistrPacket.getPayload(&tmp, sizeof(DistrMsg)));

		if(mrpkt==NULL)
		{
			dbg("SRTreeC","DistrMsgTimer.fired(): No valid payload... \n");
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
		}	


		//Aggregation every time for all chilren. If a value is lost we always have child value
		for(i = 0 ;i < MAX_CHILDREN && childrenArray[i].senderID!=0 ; i++){
			mrpkt->count += childrenArray[i].count;
			mrpkt->sum += childrenArray[i].sum;
			mrpkt->max = maxFinder(childrenArray[i].max, mrpkt->max);
		}


	
		/** root case print everything*/
		if(TOS_NODE_ID == 0){
			roundCounter+=1;

			dbg("SRTreeC", "\n\n########################Epoch %d completed#####################\n", roundCounter);
			rootMsgPrint(mrpkt);
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
					post sendDistrTask();
				}
			
			}
			else
			{
				dbg("SRTreeC","DistrMsg failed to be enqueued in SendingQueue!!!");
			}

		}		
	}


	event void DistrAMSend.sendDone(message_t * msg , error_t err)
	{

		setDistrSendBusy(FALSE);
		
	}

	event message_t* DistrReceive.receive( message_t* msg , void* payload , uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource = call DistrAMPacket.source(msg);
		
		
		atomic{
			memcpy(&tmp,msg,sizeof(message_t));
		}
		enqueueDone=call DistrReceiveQueue.enqueue(tmp);
		
		if( enqueueDone== SUCCESS)
		{
			post receiveDistrTask();
		}
		else
		{
			dbg("SRTreeC","DistrMsg enqueue failed!!! \n");
			
		}
		
		return msg;
	}
	
	
	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);
		
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		}
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			post receiveRoutingTask();
		}
		else
		{
			dbg("SRTreeC","RoutingMsg enqueue failed!!! \n");			
		}
		
		return msg;
	}
	
	
	/***************************SEND TASKS****************************/
	
	
	task void sendRoutingTask()
	{

		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;


		/**The simulation never reaches the statements below but will not be deleted
		for plentitude*/
		if (call RoutingSendQueue.empty())
		{
			dbg("SRTreeC","sendRoutingTask(): Q is empty!\n");
			return;
		}
		
		
		if(RoutingSendBusy)
		{
			dbg("SRTreeC","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue();
		
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
			setRoutingSendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","send failed!!!\n");

	
		}
	}
	

	task void sendDistrTask()
	{
		uint8_t mlen;
		error_t sendDone;
		uint16_t mdest;
		DistrMsg* mpayload;
		

		/**The simulation never reaches the statements below but will not be deleted
		for plentitude*/
		if (call DistrSendQueue.empty())
		{
			dbg("SRTreeC","sendDistrTask(): Q is empty!\n");
			return;
		}

		if(DistrSendBusy == TRUE)
		{
			dbg("SRTreeC", "sendDistrTask(): Q is empty!\n");
			return;
		}
		
		radioDistrSendPkt = call DistrSendQueue.dequeue();
		mlen=call DistrPacket.payloadLength(&radioDistrSendPkt);
		mpayload= call DistrPacket.getPayload(&radioDistrSendPkt,mlen);
		
		if(mlen!= sizeof(DistrMsg))
		{
			dbg("SRTreeC", "\t\t sendDistrTask(): Unknown message!!\n");
			return;
		}
		

		mdest= call DistrAMPacket.destination(&radioDistrSendPkt);
		
		sendDone=call DistrAMSend.send(mdest,&radioDistrSendPkt, mlen);
		
		if ( sendDone== SUCCESS)
		{

			setDistrSendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","sendDistrTask(): Send returned failed!!!\n");

		}
	}

	/***************************RECEIVE TASKS****************************/
	
	task void receiveRoutingTask()
	{
		message_t tmp;
		uint8_t len;
		message_t radioRoutingRecPkt;
		

		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue(); /*dequeues a message and processes it*/
		
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		
				
		if(len == sizeof(RoutingMsg))
		{
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));
			

			/**In that case we don't have a father yet*/
			if ( (parentID<0)||(parentID>=65535))
			{

				parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);
				curdepth= mpkt->depth + 1;
		
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
			
		}
		else
		{
			dbg("SRTreeC","receiveRoutingTask():Empty message!!! \n");
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
		

		radioDistrRecPkt= call DistrReceiveQueue.dequeue();
		
		len= call DistrPacket.payloadLength(&radioDistrRecPkt);

		source = call DistrAMPacket.source(&radioDistrRecPkt);
		
		/**Check if received a message*/
		if(len == sizeof(DistrMsg))
		{
			
			DistrMsg* mr = (DistrMsg*) (call DistrPacket.getPayload(&radioDistrRecPkt,len));

			/** Add new child to cache*/
			for(i=0; i< MAX_CHILDREN ; i++){
				if(source == childrenArray[i].senderID || childrenArray[i].senderID == 0){
					childrenArray[i].senderID = source;
					childrenArray[i].count = mr->count;
					childrenArray[i].sum = mr->sum;
					childrenArray[i].max = mr->max;
					break;

				}
				/**
					Still haven't found from the children array the right
					destination
				*/
				
			}
			
		}
		else
		{
			dbg("SRTreeC","receiveDistrTask():Empty message!!! \n");
			return;
		}
		
	}
	 
	
}
