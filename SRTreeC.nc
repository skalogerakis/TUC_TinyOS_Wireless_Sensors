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
	uint16_t chooseQues;
	uint16_t parentID;
	uint8_t i;
	uint16_t startPer;

	

	uint16_t slotTime;
	uint16_t subSlotSplit;
	uint16_t subSlotChoose;
	uint16_t timerCounter;
	uint16_t Vold;

	//double tct = (double)TCT/(double)PERCENTAGE;


	uint8_t numMsgSent;


	uint8_t numFun;
	uint8_t chooseFun1;
	uint8_t chooseFun2;
	uint8_t chooseFun;
	uint8_t chooseProg=1;	//default program choose. Only when 2.2 change
	uint8_t oldFlag = 0;


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

	 //DONT FORGET TO INITIALIZE AND ADD TO STRUCT
	/**Initialize children array with default values. Min val is 0 and max val is 50 so initialize min/max in an appropriate way*/
	void InitChildrenArray()
	{
		for(i=0; i< MAX_CHILDREN; i++){
			childrenArray[i].senderID = 0;
			childrenArray[i].sum = 0;
			childrenArray[i].count = 0;
			childrenArray[i].sumofSquares = 0;
			childrenArray[i].max = 0;
			childrenArray[i].min = 100;
		}
		
	}


	/**Used to print all needed messages in the case where we send 4 messages*/
	void rootMsgPrint4(DistrMsg4* mrpkt)
	{
		dbg("SRTreeC", "#### OUTPUT: \n");
		//dbg("SRTreeC", "#### [COUNT] = %d\n", mrpkt->field4b);
		//dbg("SRTreeC", "#### [SUM] = %d\n", mrpkt->field4a);
		if(chooseFun1 == 1 || chooseFun2 ==1){	//min case
			dbg("SRTreeC", "#### [MIN] = %d\n", mrpkt->field4d);
		}else{	//max case
			dbg("SRTreeC", "#### [MAX] = %d\n", mrpkt->field4d);
		}
		//dbg("SRTreeC", "#### [SUM OF SQUARES] = %d\n\n\n", mrpkt->field4c);
		dbg("SRTreeC", "#### [VARIANCE] = %d\n\n\n", (mrpkt->field4c/mrpkt->field4b-(mrpkt->field4a/mrpkt->field4b)*(mrpkt->field4a/mrpkt->field4b)));
		
	}

	void rootMsgPrint3(DistrMsg3* mrpkt)
	{
		dbg("SRTreeC", "#### OUTPUT: \n");
		if(chooseFun==6){
			dbg("SRTreeC", "#### [VARIANCE] = %d\n\n\n", mrpkt->field3c/mrpkt->field3b-(mrpkt->field3a/mrpkt->field3b)*(mrpkt->field3a/mrpkt->field3b));
		}
		else if(chooseFun1==6 || chooseFun2==6){ //Two functions. One of them is VARIANCE
           dbg("SRTreeC", "#### [VARIANCE] = %d\n", mrpkt->field3c/mrpkt->field3b-(mrpkt->field3a/mrpkt->field3b)*(mrpkt->field3a/mrpkt->field3b));
		   if(chooseFun1==5 || chooseFun2==5){ // case SUM
              dbg("SRTreeC", "#### [SUM] = %d\n\n\n", mrpkt->field3a);
		   }
		   else if(chooseFun1==3 || chooseFun2==3){ //case COUNT
              dbg("SRTreeC", "#### [COUNT] = %d\n\n\n", mrpkt->field3b);
		   }
		   else{ // case AVG
		   	  dbg("SRTreeC", "#### [AVG] = %d\n\n\n", mrpkt->field3a/mrpkt->field3b);
		   }
		}
		else if(chooseFun1==1 || chooseFun2==1 || chooseFun1==2 || chooseFun2==2){ // case AVG + (MAX or MIN)
           dbg("SRTreeC", "#### [AVG] = %d\n", mrpkt->field3a/mrpkt->field3b);
           if(chooseFun1 == 1 || chooseFun2 ==1){	//min case
			dbg("SRTreeC", "#### [MIN] = %d\n\n\n", mrpkt->field3c);
		   }else{	//max case
			dbg("SRTreeC", "#### [MAX] = %d\n\n\n", mrpkt->field3c);
		   } 
		}
	}

	void rootMsgPrint2(DistrMsg2* mrpkt)
	{
		dbg("SRTreeC", "#### OUTPUT: \n");
		if (numFun==1 && chooseFun==4){
			dbg("SRTreeC", "#### [AVG] = %d\n\n\n", mrpkt->field2a/mrpkt->field2b);
		}
		else if(chooseFun1==1 || chooseFun2==1 || chooseFun1==2 || chooseFun2==2){ //At least one (min/max) function
            if((chooseFun1==1 || chooseFun2==1) && (chooseFun1==2 || chooseFun2==2)){ // min AND max
            	dbg("SRTreeC", "#### [MIN] = %d\n", mrpkt->field2a);
            	dbg("SRTreeC", "#### [MAX] = %d\n\n\n", mrpkt->field2b);
            }
            else {
                if(chooseFun1==5 || chooseFun2==5) // SUM + (MIN or MAX)
                    dbg("SRTreeC", "#### [SUM] = %d\n", mrpkt->field2a);
                else    // COUNT + (MIN or MAX)
                    dbg("SRTreeC", "#### [COUNT] = %d\n", mrpkt->field2a); 
                if(chooseFun1 == 1 || chooseFun2 == 1){	//case min
					dbg("SRTreeC", "#### [MIN] = %d\n\n\n", mrpkt->field2b);
				}else if(chooseFun1 == 2 || chooseFun2 == 2){ //case max
					dbg("SRTreeC", "#### [MAX] = %d\n\n\n", mrpkt->field2b);
				}
            }
		}
		else if(numFun==2 && (chooseFun1==4 || chooseFun2==4)){ // One function is AVG
                dbg("SRTreeC", "#### [AVG] = %d\n", mrpkt->field2a/mrpkt->field2b);
                if(chooseFun1==3 || chooseFun2==3)
                   dbg("SRTreeC", "#### [COUNT] = %d\n\n\n", mrpkt->field2b);
                else
                   dbg("SRTreeC", "#### [SUM] = %d\n\n\n", mrpkt->field2a);      
		}
		else if((chooseFun1==3 || chooseFun2==3) && (chooseFun1==5 || chooseFun2==5)){ //case SUM + COUNT
				  dbg("SRTreeC", "#### [COUNT] = %d\n", mrpkt->field2b);
				  dbg("SRTreeC", "#### [SUM] = %d\n\n\n", mrpkt->field2a);	
		}
	}



	/**Used to print all needed messages in the case where we send 1 message*/
	void rootMsgPrint1(DistrMsg1* mrpkt)
	{
		dbg("SRTreeC", "#### OUTPUT: \n");

		if(chooseFun == 1){	//min case
			dbg("SRTreeC", "#### [MIN] = %d\n\n\n", mrpkt->field1a);
		}else if(chooseFun == 2){	//max case
			dbg("SRTreeC", "#### [ΜΑΧ] = %d\n\n\n", mrpkt->field1a);
		}else if(chooseFun == 3){	//count case
			dbg("SRTreeC", "#### [COUNT] = %d\n\n\n", mrpkt->field1a);
		}else{	//sum case
			dbg("SRTreeC", "#### [SUM] = %d\n\n\n", mrpkt->field1a);
		}
		
	}


	/**This function returns max*/
	uint8_t maxFinder(uint16_t a, uint16_t b){
		return (a > b) ? a : b;
	}

	/**This function returns min*/
	uint8_t minFinder(uint16_t a, uint16_t b){
		return (a < b) ? a : b;
	}
	
	uint8_t nDigits;
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
			Vold = 0;
		}
		else
		{
			curdepth=-1;
			parentID=-1;
			Vold = 0;
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
		uint16_t fDigit;
		uint8_t lDigit;
		

		//dbg("SRTreeC", "FIRST %d\n", fDigit);
		slotTime = EPOCH/(MAX_DEPTH+1);
		subSlotSplit = (MAX_DEPTH);

		subSlotChoose = (MAX_DEPTH - curdepth);



		/**Find aggregation functions used.Since the functions don't change during
		runtime and need to be calculated just once. Here is the place where will be
		the fewest calculations possible*/

		

		nDigits = floor(log10(abs(chooseQues)))+1;	/*Use some maths to calculate number length*/
		dbg("SRTreeC", "CHECK %d, chooseQues %d\n", nDigits, chooseQues);

		switch(nDigits){
			case 1:
				//dbg("SRTreeC", "One digit");
				numMsgSent = 1;
				if(chooseQues < 5){
					//case 2.1 with one aggregation
					chooseProg = 1;
					chooseFun = chooseQues;
				}else{
					//case 2.2
					chooseProg = 2;
					chooseFun = chooseQues - 5;
					if(chooseFun == 4){
						chooseFun = 5;
					}
				}
				numFun = 1;
				
				break;
			case 2:
				//dbg("SRTreeC", "Two digits");
				numMsgSent = 2;
				chooseProg = 1;
				break;
			case 3:
				//dbg("SRTreeC", "Three digits");
				numMsgSent = 3;
				chooseProg = 1;
				break;
			default :	
				//case 4
				//dbg("SRTreeC", "Four digits");
				numMsgSent = 4;
				chooseProg = 1;
				break;
		}

		if(nDigits!= 1){
			fDigit = chooseQues;
			lDigit = chooseQues % 10;	/*Calculate last digit of number*/
			
			//dbg("SRTreeC", "First %d\n", fDigit);
			atomic{	/*Calculate first digit of number*/
				while(fDigit >= 10){
				fDigit/=10;
				}
			}
			

			//dbg("SRTreeC", "First %d, last %d\n", fDigit, lDigit);

			if(lDigit != 0){
				numFun = 2;
				chooseFun1 = fDigit;
				chooseFun2 = lDigit;
			}else{
				numFun = 1;
				chooseFun = fDigit;
			}
		}
		
		dbg("SRTreeC", "GENIUS BITCHESSSSS numFun %d,chooseProg %d , chooseFun %d , chooseFun1 %d, chooseFun2 %d\n", numFun,chooseProg, chooseFun, chooseFun1, chooseFun2);


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

	//ALMOST DONE PHASE 2
	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;

		if(TOS_NODE_ID == 0){
				/**
					1. MIN
					2. MAX
					3. COUNT
					4. AVG
					5. SUM
					6. VARIANCE
				*/

		/*		The technique we used to send the least amount of messages is based on encoding/decoding.
				To be more specific, we send in Routing an extra message ques which includes
				info about all the aggregations used in all possible ways. First, we check
				the number of messages that the random combination of aggreagations will sent(choose suitable struct
				afterwards). This will be our final's integer size. Then, we assign the numbers of the aggregates used
				(from the number map above) one as a first digit of a number and one as last digit. If last digit is 0
				then we have only 1 aggregate. In case, we have 1 message sent(struct DistrMsg1) the numbers from
				1 to 4 are used in 2.1 program whereas from 6 to 9 are referring to program 2.2

				Ex. sent = 6001, number of messages 4(struct DistrMsg4) as sent.length = 4, and aggregation functions
				6(Variance) and 1(Min) will be used.

		*/
				//TODO RAND
			chooseProg= 1;

			if(chooseProg == 1){	//case 2.1 question is chosen
				numFun = 2;

				if(numFun == 2){

					chooseFun1 = 1;
					chooseFun2 = 4;
	
					//TODO must check that random numbers always differ
					if((chooseFun1 == 1 || chooseFun2 == 1) || (chooseFun1 == 2 || chooseFun2 == 2)){	/** Case that one of the given choices is MIN or MAX*/
		
						if(chooseFun1 == 6 || chooseFun2 == 6){	//case that one of the choices is VARIANCE
							//case 4
							numMsgSent = 4;
							chooseQues = chooseFun1 * 1000 + chooseFun2;
						}
						else if(chooseFun1 == 4 || chooseFun2 == 4){	//case that one of the choises is AVG
							//case 3
							numMsgSent = 3;
							chooseQues = chooseFun1 * 100 + chooseFun2;
						}
						else if((chooseFun1 == 3 || chooseFun2 == 3) || (chooseFun1 == 5 || chooseFun2 == 5)){	//case that one of the choises is COUNT, SUM
							//case 2
							numMsgSent = 2;
							chooseQues = chooseFun1 * 10 + chooseFun2;
						}

						if((chooseFun1 == 1 && chooseFun2 == 2) || (chooseFun1 == 2 && chooseFun2 == 1)){
							//case 1
							numMsgSent = 2;
							chooseQues = chooseFun1 * 10 + chooseFun2;
						}
					}else if(chooseFun1 == 6 || chooseFun2 == 6){ /**case one of the choises is VARIANCE*/
						//case 3 for all cases
						numMsgSent = 3;
						chooseQues = chooseFun1 * 100 + chooseFun2;

					}else{	/**Case that the choices are SUM, COUNT or AVG */
						//case 2 for all cases
						numMsgSent = 2;
						chooseQues = chooseFun1 * 10 + chooseFun2;


					}

				}else{
					chooseFun =6; //chooseFun is when one aggregation is chosen
					if(chooseFun == 6){	//case that the choice is VARIANCE
						//case 3
						numMsgSent = 3;
						chooseQues = chooseFun * 100;
					
					}
					else if(chooseFun == 4){	//case that the choice is AVG
					//case 2
						numMsgSent = 2;
						chooseQues = chooseFun * 10;
					}
					else{	//case that the choice is MIN, MAX, COUNT, SUM
					//case 1
						numMsgSent = 1;
						chooseQues = chooseFun;
					}
				}
			}else{

				/**
					1. MIN
					2. MAX
					3. COUNT
					5. SUM

					In order to be consistent about our statements, we don't mess with
					the previous order of the function. We choose a random value from 1 to 4.
					If 4 is chosen we assign it value 5.
				*/
				chooseFun= 4;

				// if(chooseFun == 4){
				// 	chooseFun = 5;
				// }

				numMsgSent = 1;
				//TODO CHECK IF
				chooseQues = chooseFun+5;	
			}

			

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
		//todo must add another variable
		atomic{
			mrpkt->ques = chooseQues;
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

		DistrMsg1* mrpkt1;
		DistrMsg2* mrpkt2;
		DistrMsg3* mrpkt3;
		DistrMsg4* mrpkt4;

		

		/**The simulation never reaches the statements below but will not be deleted
		for plentitude*/
		if(call DistrSendQueue.full())
		{
			dbg("SRTreeC", "DistrSendQueue is FULL!!! \n");
			return;
		}
		
		randVal = call RandomGen.rand16() % 50;

		dbg("SRTreeC", "Random value generated %d\n", randVal);
		// mrpkt = (DistrMsg*) (call DistrPacket.getPayload(&tmp, sizeof(DistrMsg)));

		if(numMsgSent == 1){
			mrpkt1 = (DistrMsg1*) (call DistrPacket.getPayload(&tmp, sizeof(DistrMsg1)));

			if(chooseFun == 3){		/*case COUNT is choosen*/
				mrpkt1->field1a = 1;
			}else{	/*In every other case*/
				mrpkt1->field1a = randVal;
			}

			//Aggregation every time for all chilren. If a value is lost we always have child value
			for(i = 0 ;i < MAX_CHILDREN && childrenArray[i].senderID!=0 ; i++){
				if(chooseFun == 1){	//min case
					mrpkt1->field1a = minFinder(childrenArray[i].min, mrpkt1->field1a);
				}else if( chooseFun == 2){	//max case
					mrpkt1->field1a = maxFinder(childrenArray[i].max, mrpkt1->field1a);
				}else if( chooseFun == 3){	//count case
					mrpkt1->field1a += childrenArray[i].count; 
				}else if( chooseFun == 5){	//sum case
					mrpkt1->field1a += childrenArray[i].sum; 
				}

			}

			if(mrpkt1==NULL)
			{
		 		dbg("SRTreeC","DistrMsgTimer.fired(): No valid payload... \n");
		 		return;
		 	}


		}else if(numMsgSent == 2){

			/** 
            Check all possible combinations where we need two attributes 
            */
			mrpkt2 = (DistrMsg2*) (call DistrPacket.getPayload(&tmp, sizeof(DistrMsg2)));
	
            
            if(chooseFun==4 || (chooseFun1!=1 && chooseFun2!=1 && chooseFun1!=2 && chooseFun2!=2)){ // cases where only COUNT,SUM are needed
                atomic{
					mrpkt2->field2a = randVal;	/*used as sum*/
					mrpkt2->field2b = 1;	/*used as count*/
				}

				/*Aggregation of values*/
			    for(i = 0 ;i < MAX_CHILDREN && childrenArray[i].senderID!=0 ; i++){
					mrpkt2->field2a += childrenArray[i].sum;
					mrpkt2->field2b += childrenArray[i].count;  
			    }
			}
			else if(chooseFun1==1 || chooseFun2==1 || chooseFun1==2 || chooseFun2==2){ // cases with at least one (min/max) function
               if((chooseFun1==1 || chooseFun2==1) && (chooseFun1==2 || chooseFun2==2)){ //min AND max case
                   atomic{
					mrpkt2->field2a = randVal;	/*used as min*/
					mrpkt2->field2b = randVal;	/*used as max*/
			       }

			        /*Aggregation of values*/
				    for(i = 0 ;i < MAX_CHILDREN && childrenArray[i].senderID!=0 ; i++){
						mrpkt2->field2a = minFinder(childrenArray[i].min, mrpkt2->field2a);
						mrpkt2->field2b = maxFinder(childrenArray[i].max, mrpkt2->field2b);   
				    }
                }
                else if(chooseFun1==5 || chooseFun2==5){  // AVG + (MIN or MAX)
                    atomic{
						mrpkt2->field2a = randVal;	/*used as sum*/
						mrpkt2->field2b = randVal;	/*used as min or max*/
				    }
                    
                    /*Aggregation of values*/
                    for(i = 0 ;i < MAX_CHILDREN && childrenArray[i].senderID!=0 ; i++){
						mrpkt2->field2a += childrenArray[i].sum;
						if(chooseFun1==1 || chooseFun2==1) // case min
						   mrpkt2->field2b = minFinder(childrenArray[i].min, mrpkt2->field2b);
						else // case max
						   mrpkt2->field2b = maxFinder(childrenArray[i].max, mrpkt2->field2b);   
			        }
                }
                else{ // case COUNT + (MAX or MIN)
                	atomic{
						mrpkt2->field2a = 1;	/*used as count*/
						mrpkt2->field2b = randVal;	/*used as min or max*/
				    }

				    /*Aggregation of values*/
				    for(i = 0 ;i < MAX_CHILDREN && childrenArray[i].senderID!=0 ; i++){
						mrpkt2->field2a += childrenArray[i].count;
						if(chooseFun1==1 || chooseFun2==1) // case min
						   mrpkt2->field2b = minFinder(childrenArray[i].min, mrpkt2->field2b);
						else // case max
						   mrpkt2->field2b = maxFinder(childrenArray[i].max, mrpkt2->field2b);   
				    }
                }
			}
			 

			if(mrpkt2==NULL)
			{
		 		dbg("SRTreeC","DistrMsgTimer.fired(): No valid payload... \n");
		 		return;
		 	}
		}else if(numMsgSent == 3){
			/** 
            Check all possible combinations where we need three attributes 
            */    
			mrpkt3 = (DistrMsg3*) (call DistrPacket.getPayload(&tmp, sizeof(DistrMsg3)));

            if(numFun==2 && (chooseFun1==1 || chooseFun2==1 || chooseFun1==2 || chooseFun2==2)){  //Definitely case AVG + (MIN or MAX)
				atomic{
				mrpkt3->field3a = randVal;	/*used as sum*/
				mrpkt3->field3b = 1;	/*used as count*/
				mrpkt3->field3c = randVal; /*used as min or max */
			    }

                /*Aggregation of values*/
			    for(i = 0 ;i < MAX_CHILDREN && childrenArray[i].senderID!=0 ; i++){
					mrpkt3->field3a += childrenArray[i].sum;
					mrpkt3->field3b += childrenArray[i].count;
					if(chooseFun1==1 || chooseFun2==1) // case min
					   mrpkt3->field3c = minFinder(childrenArray[i].min, mrpkt3->field3c);
					else // case max
					   mrpkt3->field3c = maxFinder(childrenArray[i].max, mrpkt3->field3c);   
			    } 
			}else{   // cases VARIANCE, VARIANCE + SUM, VARIANCE + COUNT, VARIANCE + AVG all need the same attributes
                atomic{
				mrpkt3->field3a = randVal;	/*used as sum*/
				mrpkt3->field3b = 1;	/*used as count*/
				mrpkt3->field3c = randVal * randVal; /*used as sumofSquares*/
			    }

                /*Aggregation of values*/
			    for(i = 0 ;i < MAX_CHILDREN && childrenArray[i].senderID!=0 ; i++){
				mrpkt3->field3a += childrenArray[i].sum;
				mrpkt3->field3b += childrenArray[i].count;
				mrpkt3->field3c += childrenArray[i].sumofSquares;
			    }
			}

			if(mrpkt3==NULL)
			{
		 		dbg("SRTreeC","DistrMsgTimer.fired(): No valid payload... \n");
		 		return;
		 	}
		}else{
			/**
				All combination of the aggregation functions in this case 
				produces every time sum, sumofSquares and count. Only the fourth
				parameter changes
			*/
			mrpkt4 = (DistrMsg4*) (call DistrPacket.getPayload(&tmp, sizeof(DistrMsg4)));

			
			atomic{
				mrpkt4->field4a = randVal;	/*used as sum*/
				mrpkt4->field4b = 1;	/*used as count*/
				mrpkt4->field4c = randVal * randVal; /*used as sumofSquares*/
				mrpkt4->field4d = randVal;/*used as min or max*/
			}	


			//Aggregation every time for all chilren. If a value is lost we always have child value
			for(i = 0 ;i < MAX_CHILDREN && childrenArray[i].senderID!=0 ; i++){
				mrpkt4->field4b += childrenArray[i].count;
				mrpkt4->field4a += childrenArray[i].sum;
				mrpkt4->field4c += childrenArray[i].sumofSquares;
				if(chooseFun1 == 1 || chooseFun2 == 1){	//case MIN
					mrpkt4->field4d = minFinder(childrenArray[i].min, mrpkt4->field4d);
				}else{	//case MAX
					mrpkt4->field4d = maxFinder(childrenArray[i].max, mrpkt4->field4d);
				}

			}

			if(mrpkt4==NULL)
			{
		 		dbg("SRTreeC","DistrMsgTimer.fired(): No valid payload... \n");
		 		return;
		 	}

		}

	
		/** root case print everything*/
		if(TOS_NODE_ID == 0){
			roundCounter+=1;

			dbg("SRTreeC", "\n\n########################Epoch %d completed#####################\n", roundCounter);

			if(numMsgSent == 1){
				rootMsgPrint1(mrpkt1);
			}else if(numMsgSent == 2){
				rootMsgPrint2(mrpkt2);
			}else if(numMsgSent == 3){
				rootMsgPrint3(mrpkt3);
			}else{
				rootMsgPrint4(mrpkt4);
			}

		}
		else /** case we don't have root node then sent everything to the parent*/
		{

			//dbg("SRTreeC", "Node: %d , Parent: %d, Sum: %d, count: %d, max: %d , depth: %d\n",TOS_NODE_ID,parentID, mrpkt->sum, mrpkt->count, mrpkt->max, curdepth);
			call DistrAMPacket.setDestination(&tmp, parentID);
			// call DistrPacket.setPayloadLength(&tmp, sizeof(DistrMsg));

			// if(chooseProg != 2 && ){

			

			if(numMsgSent == 1){	

				//dbg("SRTreeC","Old value %d\n", Vold);
				/**
					In that section, we implement TINA. We know as a fact that both numbers
					are positive,so we can compare their aggregate values not only in the 
					leaves but in the whole tree. So if the statement below is true, just keep
					the old values to minimize messages sent. TCT is defined in SimpleRoutingTree.h
				*/
				if(chooseProg == 2 && !(abs(mrpkt1->field1a - Vold) > abs(Vold) * ((double)TCT/(double)PERCENTAGE))){	//don't change value
					oldFlag = 1;
					dbg("SRTreeC","Don't send message with new value %d and old value %d\n", mrpkt1->field1a, Vold);
				}else if( chooseProg == 2){	//change value and update old
					oldFlag = 0;
					Vold = mrpkt1->field1a;
				}

				if(oldFlag == 0){
					
				
					call DistrPacket.setPayloadLength(&tmp, sizeof(DistrMsg1));

					if(chooseFun == 1){	//min case
						dbg("SRTreeC", "Node: %d , Parent: %d, min: %d, depth: %d\n",TOS_NODE_ID,parentID, mrpkt1->field1a,curdepth);
					}else if( chooseFun == 2){	//max case
						dbg("SRTreeC", "Node: %d , Parent: %d, max: %d, depth: %d\n",TOS_NODE_ID,parentID, mrpkt1->field1a,curdepth);
					}else if(chooseFun == 3){	//count case
						dbg("SRTreeC", "Node: %d , Parent: %d, count: %d, depth: %d\n",TOS_NODE_ID,parentID, mrpkt1->field1a,curdepth);
					}else{	// sum count
						dbg("SRTreeC", "Node: %d , Parent: %d, sum: %d, depth: %d\n",TOS_NODE_ID,parentID, mrpkt1->field1a,curdepth);
					}

				}
				// 	dbg("SRTreeC","Don't send message with new value %d and old value %d\n", mrpkt1->field1a, Vold);
				// }
			}else if(numMsgSent == 2){
				call DistrPacket.setPayloadLength(&tmp, sizeof(DistrMsg2));
				dbg("SRTreeC", "Node: %d , Parent: %d, Par_1: %d, Par_2: %d, depth: %d\n",TOS_NODE_ID,parentID, mrpkt2->field2a, mrpkt2->field2b,curdepth);

			}else if(numMsgSent == 3){
				call DistrPacket.setPayloadLength(&tmp, sizeof(DistrMsg3));
				dbg("SRTreeC", "Node: %d , Parent: %d, Sum: %d, count: %d, 3rd parameter: %d, depth: %d\n",TOS_NODE_ID,parentID, mrpkt3->field3a, mrpkt3->field3b, mrpkt3->field3c,curdepth);

			}else{
				call DistrPacket.setPayloadLength(&tmp, sizeof(DistrMsg4));

				if(chooseFun1 == 1 || chooseFun2 == 1){	//min case
					dbg("SRTreeC", "Node: %d , Parent: %d, Sum: %d, count: %d, min: %d ,sum of squares %d, depth: %d\n",TOS_NODE_ID,parentID, mrpkt4->field4a, mrpkt4->field4b, mrpkt4->field4d,mrpkt4->field4c ,curdepth);

				}else{	//max case
					dbg("SRTreeC", "Node: %d , Parent: %d, Sum: %d, count: %d, max: %d ,sum of squares %d, depth: %d\n",TOS_NODE_ID,parentID, mrpkt4->field4a, mrpkt4->field4b, mrpkt4->field4d,mrpkt4->field4c ,curdepth);

				}

			}
			
			if(oldFlag == 0){
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
			

			// }else{
			// 	dbg("SRTreeC","Don't send message with new value %d and old value %d\n", mrpkt1->field1a, Vold)
			// }

		}		
	}

	//DONE FOR PHASE 2
	event void DistrAMSend.sendDone(message_t * msg , error_t err)
	{

		setDistrSendBusy(FALSE);
		
	}

	//DONE FOR PHASE 2
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
	
	//DONE FOR PHASE 2
	task void sendDistrTask()
	{
		uint8_t mlen;
		error_t sendDone;
		uint16_t mdest;
		DistrMsg* mpayload;

		DistrMsg1* mpayload1;
		DistrMsg2* mpayload2;
		DistrMsg3* mpayload3;
		DistrMsg4* mpayload4;
		

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

		//PHASE 2
		if(numMsgSent == 1){
			mpayload1= call DistrPacket.getPayload(&radioDistrSendPkt,mlen);

			if(mlen!= sizeof(DistrMsg1))
			{
				dbg("SRTreeC", "\t\t sendDistrTask(): Unknown message!!\n");
				return;
			}

		}else if(numMsgSent == 2){
			mpayload2= call DistrPacket.getPayload(&radioDistrSendPkt,mlen);

			if(mlen!= sizeof(DistrMsg2))
			{
				dbg("SRTreeC", "\t\t sendDistrTask(): Unknown message!!\n");
				return;
			}

		}else if(numMsgSent == 3){
			mpayload3= call DistrPacket.getPayload(&radioDistrSendPkt,mlen);

			if(mlen!= sizeof(DistrMsg3))
			{
				dbg("SRTreeC", "\t\t sendDistrTask(): Unknown message!!\n");
				return;
			}

		}else{
			mpayload4= call DistrPacket.getPayload(&radioDistrSendPkt,mlen);

			if(mlen!= sizeof(DistrMsg4))
			{
				dbg("SRTreeC", "\t\t sendDistrTask(): Unknown message!!\n");
				return;
			}
		}

		
		// if(mlen!= sizeof(DistrMsg))
		// {
		// 	dbg("SRTreeC", "\t\t sendDistrTask(): Unknown message!!\n");
		// 	return;
		// }
		

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
				chooseQues = mpkt->ques;
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


	//NEEDS WORK
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

		//TODO ADDED CASES
		if(numMsgSent == 1){
			/**Check if received a message*/
			if(len == sizeof(DistrMsg1))
			{
			
				DistrMsg1* mr = (DistrMsg1*) (call DistrPacket.getPayload(&radioDistrRecPkt,len));

				/** Add new child to cache*/
				for(i=0; i< MAX_CHILDREN ; i++){
					if(source == childrenArray[i].senderID || childrenArray[i].senderID == 0){
						childrenArray[i].senderID = source;

						if(chooseFun == 1){	//min case
							childrenArray[i].min = mr->field1a;
						}else if( chooseFun == 2){	//max case
							childrenArray[i].max = mr->field1a;
						}else if( chooseFun == 3){	//count case
							childrenArray[i].count = mr->field1a;
						}else if(chooseFun == 5){	//sum case
							childrenArray[i].sum = mr->field1a;
						}
						
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

		}else if(numMsgSent == 2){
			/**Check if received a message*/
			if(len == sizeof(DistrMsg2))
			{
			
				DistrMsg2* mr = (DistrMsg2*) (call DistrPacket.getPayload(&radioDistrRecPkt,len));

				/** Add new child to cache*/
				for(i=0; i< MAX_CHILDREN ; i++){
					if(source == childrenArray[i].senderID || childrenArray[i].senderID == 0){
						childrenArray[i].senderID = source;
						if(chooseFun==4 || (chooseFun1!=1 && chooseFun2!=1 && chooseFun1!=2 && chooseFun2!=2)){
							childrenArray[i].sum = mr->field2a;
							childrenArray[i].count = mr->field2b;
						}
						else if(chooseFun1==1 || chooseFun2==1 || chooseFun1==2 || chooseFun2==2){ //At least one (min/max) function
                           if((chooseFun1==1 || chooseFun2==1) && (chooseFun1==2 || chooseFun2==2)){ // min AND max
                               childrenArray[i].min = mr->field2a;
                               childrenArray[i].max = mr->field2b;
                           }
                           else {
                           	   if(chooseFun1==5 || chooseFun2==5) // SUM + (MIN or MAX)
                                  childrenArray[i].sum = mr->field2a;
                               else    // COUNT + (MIN or MAX)
                                  childrenArray[i].count = mr->field2a; 
                                if(chooseFun1 == 1 || chooseFun2 == 1){	//case min
								childrenArray[i].min = mr->field2b;
							   }else if(chooseFun1 == 2 || chooseFun2 == 2){ //case max
								childrenArray[i].max = mr->field2b;
							   }
                           }
						}
						
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

		}else if(numMsgSent == 3){
			/**Check if received a message*/
			if(len == sizeof(DistrMsg3))
			{
			
				DistrMsg3* mr = (DistrMsg3*) (call DistrPacket.getPayload(&radioDistrRecPkt,len));

				/** Add new child to cache*/
				for(i=0; i< MAX_CHILDREN ; i++){
					if(source == childrenArray[i].senderID || childrenArray[i].senderID == 0){
						childrenArray[i].senderID = source;
						childrenArray[i].sum = mr->field3a;
						childrenArray[i].count = mr->field3b;
						childrenArray[i].sumofSquares = mr->field3c;						
						if(chooseFun1 == 1 || chooseFun2 == 1){	//case min (+ avg)
							childrenArray[i].min = mr->field3c;
						}else if(chooseFun1 == 2 || chooseFun2 == 2){ //case max (+ avg)
							childrenArray[i].max = mr->field3c;
						}
						
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

		}else{
			/**Check if received a message*/
			if(len == sizeof(DistrMsg4))
			{
			
				DistrMsg4* mr = (DistrMsg4*) (call DistrPacket.getPayload(&radioDistrRecPkt,len));

				/** Add new child to cache*/
				for(i=0; i< MAX_CHILDREN ; i++){
					if(source == childrenArray[i].senderID || childrenArray[i].senderID == 0){
						childrenArray[i].senderID = source;
						childrenArray[i].sum = mr->field4a;
						childrenArray[i].count = mr->field4b;
						childrenArray[i].sumofSquares = mr->field4c;
						if(chooseFun1 == 1 || chooseFun2 == 1){	//case min
							childrenArray[i].min = mr->field4d;
						}else{
							childrenArray[i].max = mr->field4d;	//case min
						}
						
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


	/****************************ENCODING/DECODING TASKS**************************/


	
}

