--
--  Framework: Uwe R. Zimmer, Australia, 2019
--

with Exceptions; use Exceptions;
with Protected_Queue;
package body Generic_Router is

   task body Router_Task is

      Connected_Routers : Ids_To_Links;

   begin
      accept Configure (Links : Ids_To_Links) do
         Connected_Routers := Links;
      end Configure;

      declare
         Port_List : constant Connected_Router_Ports := To_Router_Ports (Task_Id, Connected_Routers);
         -- Denfination Of Local Queues
         type QueueIndex is mod 1000;
         package Mailbox_Fifo is new Protected_Queue (Messages_Mailbox, QueueIndex);
         package Passing_Fifo is new Protected_Queue (Passing_Message, QueueIndex);
         package Broadcast_Fifo is new Protected_Queue (Routing_Links, QueueIndex);
         PickUpMailBox : Mailbox_Fifo.ProtectQueue;
         MessageHold : Passing_Fifo.ProtectQueue;
         BroadcastQueue : Broadcast_Fifo.ProtectQueue;

         -- Declare Local Routing Table
         Local_Links : Routing_Links;
         -- If local table is expired
         NeedUpdate : Boolean := True;

         -- Some extra variables
         Termination : Boolean := False;
         Signature : Router_Range := Router_Range'Invalid_Value;
         RESPONSE_TIME : constant Duration := 0.001;

      begin
         --  Replace the following accept with the code of your router
         -- (and place this accept somewhere more apporpriate)

         declare

            task BroadcastHandler is entry Start; end BroadcastHandler;
            task PassHandler is entry Start; end PassHandler;
            -- task that broadcast message to other routers
            task body BroadcastHandler is
            begin
               loop
                  accept Start;
                  for i in Port_List'Range loop
                     if not Local_Links (Port_List (i).Id).To_Is_Shutdown then
                        select
                           Port_List (i).Link.all.Broadcast (Local_Links, Task_Id, False);
                        or
                           delay RESPONSE_TIME;
                        end select;
                     end if;
                  end loop;
               end loop;
            end BroadcastHandler;
            -- task that pass message to established direction
            task body PassHandler is
               PsMsg : Passing_Message;
               QueueSize : QueueIndex;
            begin
               loop
                  accept Start;
                  QueueSize := MessageHold.Get_Size;
                  for j in 1 .. QueueSize loop
                     MessageHold.Pop (PsMsg);
                     if Local_Links (PsMsg.Destination).To_Id /= Router_Range'Invalid_Value then
                        for i in Port_List'Range loop
                           if Port_List (i).Id = Local_Links (PsMsg.Destination).To_Id then
                              select
                                 Port_List (i).Link.all.Pass_Message (PsMsg);
                              or
                                 delay RESPONSE_TIME;
                                 MessageHold.Push (PsMsg);
                              end select; exit;
                           end if;
                        end loop;
                     else
                        MessageHold.Push (PsMsg);
                     end if;
                  end loop;
               end loop;
            end PassHandler;

         begin
            -- initialize local table
            for i in Port_List'Range loop
               Local_Links (Port_List (i).Id).To_Id := Port_List (i).Id;
               Local_Links (Port_List (i).Id).To_Distance := 1;
            end loop;
            Local_Links (Task_Id).To_Id := Task_Id;
            Local_Links (Task_Id).To_Distance := 0;

            while not Termination loop
               declare begin
                  select
                     PassHandler.Start;
                  or
                     delay RESPONSE_TIME;
                  end select;
                  if NeedUpdate then
                     NeedUpdate := False;
                     select
                        BroadcastHandler.Start;
                     or
                        delay RESPONSE_TIME;
                        NeedUpdate := True;
                     end select;
                  end if;
               end;
               -- entry implementations
               -- Send&Pass rule -> If arrived then wait for client receive, else try to find the correct routing direction and pass to it.
               -- Broadcast entry -> judge if received a shutdown call, if true then broadcast to other routers, otherwise, update local table.
               select
                  accept Broadcast (Message : in Routing_Links; ID : Router_Range; SDResponse : Boolean) do
                     if SDResponse then
                        NeedUpdate := True;
                        Local_Links (ID).To_Is_Shutdown := True;
                        for i in Local_Links'Range loop
                           if Local_Links (i).To_Id = ID then
                              Local_Links (i).To_Distance := INF;
                              Local_Links (i).To_Id := Router_Range'Invalid_Value;
                           end if;
                        end loop;
                     else
                        Signature := ID;
                        BroadcastQueue.Push (Message);
                     end if;
                  end Broadcast;
               or
                  accept Shutdown do
                     Termination := True;
                     abort PassHandler;
                     abort BroadcastHandler;
                     for i in Port_List'Range loop
                        if not Local_Links (Port_List (i).Id).To_Is_Shutdown then
                           Port_List (i).Link.all.Broadcast (Local_Links, Task_Id, True);
                        end if;
                     end loop;
                  end Shutdown;
               or
                  accept Send_Message (Message : in Messages_Client) do
                     if Task_Id = Message.Destination then
                        PickUpMailBox.Push (Client2Mailb (Message, 0, Task_Id));
                     elsif Local_Links (Message.Destination).To_Distance = INF then
                        MessageHold.Push (Client2Pass (Message, 0, Task_Id));
                     else
                        MessageHold.Push (Client2Pass (Message, 1, Task_Id));
                     end if;
                  end Send_Message;
               or
                  accept Pass_Message (Message : out Passing_Message) do
                     if Task_Id = Message.Destination then
                        PickUpMailBox.Push (Pass2Mailb (Message));
                     elsif Local_Links (Message.Destination).To_Distance = INF then
                        MessageHold.Push (Message);
                     else
                        Message.Hop_Counter := Message.Hop_Counter + 1;
                        MessageHold.Push (Message);
                     end if;
                  end Pass_Message;
               or
                  delay RESPONSE_TIME;
               end select;
               -- client receive message
               if not PickUpMailBox.Is_Empty then
                  select
                     accept Receive_Message (Message : out Messages_Mailbox) do
                        PickUpMailBox.Pop (Message);
                     end Receive_Message;
                  or
                     delay RESPONSE_TIME;
                  end select;
               end if;
               -- update local table with broadcast message from other routers
               while not BroadcastQueue.Is_Empty and then Signature /= Router_Range'Invalid_Value loop
                  declare
                     BcMsg : Routing_Links;
                     BcId : constant Router_Range := Signature;
                  begin
                     BroadcastQueue.Pop (BcMsg);
                     for i in BcMsg'Range loop
                        if not BcMsg (i).To_Is_Shutdown and then not Local_Links (i).To_Is_Shutdown then
                           if BcMsg (i).To_Distance /= INF then
                              if BcMsg (i).To_Distance + 1 < Local_Links (i).To_Distance then
                                 Local_Links (i).To_Distance := BcMsg (i).To_Distance + 1;
                                 Local_Links (i).To_Id := BcId;
                                 NeedUpdate := True;
                              end if;
                           elsif Local_Links (i).To_Distance /= INF and then Local_Links (i).To_Id = BcId then
                              Local_Links (i).To_Id := Router_Range'Invalid_Value;
                              Local_Links (i).To_Distance := INF;
                              NeedUpdate := True;
                           end if;
                        elsif not Local_Links (i).To_Is_Shutdown then
                           Local_Links (i).To_Is_Shutdown := True;
                           Local_Links (i).To_Id := Router_Range'Invalid_Value;
                           Local_Links (i).To_Distance := INF;
                           NeedUpdate := True;
                        end if;
                     end loop;
                  end;
               end loop;

            end loop;
         end;
      end;
      -- Respond to multiple shutdown call
      loop
         select
            accept Shutdown;
         or
            terminate;
         end select;
      end loop;

   exception
      when Exception_Id : others => Show_Exception (Exception_Id);
   end Router_Task;

   function Client2Mailb (Message : Messages_Client; HopC : Natural; SenderId : Router_Range) return Messages_Mailbox is
      MailbMsg : Messages_Mailbox;
   begin
      MailbMsg.Sender := SenderId;
      MailbMsg.Hop_Counter := HopC;
      MailbMsg.The_Message := Message.The_Message;
      return MailbMsg;
   end Client2Mailb;

   function Client2Pass (Message : Messages_Client; HopC : Natural; SenderId : Router_Range) return Passing_Message is
      PassMsg : Passing_Message;
   begin
      PassMsg.Sender := SenderId;
      PassMsg.Hop_Counter := HopC;
      PassMsg.The_Message := Message.The_Message;
      PassMsg.Destination := Message.Destination;
      return PassMsg;
   end Client2Pass;

   function Pass2Mailb (Message : Passing_Message) return Messages_Mailbox is
      MailbMsg : Messages_Mailbox;
   begin
      MailbMsg.Sender := Message.Sender;
      MailbMsg.Hop_Counter := Message.Hop_Counter;
      MailbMsg.The_Message := Message.The_Message;
      return MailbMsg;
   end Pass2Mailb;

end Generic_Router;
