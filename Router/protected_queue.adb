package body Protected_Queue is

   protected body ProtectQueue is

      procedure Push (Element : Element_Type) is
      begin
         Queue (Tail) := Element;
         Tail := Index'Succ (Tail);
      end Push;

      procedure Pop (Element : out Element_Type) is
      begin
         if Is_Empty then
            raise Tasking_Error;
         else
            Element := Queue (Head);
            Head := Index'Succ (Head);
         end if;
      end Pop;

      function Is_Empty return Boolean is (Tail = Head);
      function Get_Size return Index is (Tail - Head);

   end ProtectQueue;

end Protected_Queue;
