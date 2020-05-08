generic
   type Element_Type is private;
   type Index is mod <>;

package Protected_Queue is

   type Queue_Type is array (Index) of Element_Type;
   protected type ProtectQueue is

      procedure Push (Element : Element_Type);
      procedure Pop (Element : out Element_Type);
      function Is_Empty return Boolean;
      function Get_Size return Index;

   private

      Queue : Queue_Type;
      Head : Index := Index'First;
      Tail : Index := Index'First;

   end ProtectQueue;

end Protected_Queue;
