class RelAddr
#  @level;
#  @addr;
  attr_accessor :level, :addr
  def initialize(l, a)
    @level = l; @addr = a;
  end
  def to_s()
    @level.to_s + "," + @addr.to_s;
  end
end

class TableE  #　名前表のエントリーの基本の型
#  @kind;    #　名前の種類　
#  @name;   #　名前のつづり
  attr_reader :name, :kind
  def initialize(id)
     @name = id
  end
  def to_s()
    @name.to_s + ":" + @kind.to_s
  end
end

class TableEval < TableE
#  @value;    #　定数の場合：値　
  attr_reader :value
  def initialize(id, k, v)
    @name = id; @kind = k; @value = v; # super(id, k)?
  end
  def to_s()
    super() + ":" + @value.to_s;
  end
end

class TableEaddr < TableE
#  @relAddr  #　変数、パラメタのアドレス
  attr_accessor :relAddr
  def initialize(id, k, level, addr)
     @name = id; @kind = k; @relAddr = RelAddr.new(level, addr)
  end
  def to_s
    super.to_s + ":" + @relAddr.to_s
  end
end

class TableEfunc < TableE
#  @pars          #　関数の場合：パラメタ数　
  attr_accessor :pars
  def initialize(id, k)
    @name = id; @kind = k; @pars = 0
  end
  def to_s
    super.to_s + ":" + @pars.to_s + " params"
  end
end

class Table
  MAXTABLE = 100;  #　名前表の最大長さ　　
  MAXLEVEL =   5;  #  ブロックの最大レベル
  attr_reader :level
  def initialize(printTable)
    @printTable = printTable
    @nameTable = Array.new(MAXTABLE)  # 名前表
    @tIndex = 0      #　名前表のインデックス　
    @level = -1      #　現在のブロックレベル　
    @index = Array.new(MAXLEVEL)   #　index[i]にはブロックレベルiの最後のインデックス
    @addr  = Array.new(MAXLEVEL)    #　addr[i]にはブロックレベルiの最後の変数の番地
  # @localAddr      #　現在のブロックの最後の変数の番地　
  # @tfIndex        #　関数名の名前表でのインデックス　
  end

  def blockBegin(firstAddr)
    if @level == -1 then      #　主ブロックの時、初期設定　
        @localAddr = firstAddr
        @tIndex = 0
        @level += 1
        return
    end
    if @level == MAXLEVEL-1 then
        errorF("too many nested blocks")
    end
    @index[@level] = @tIndex    #　今までのブロックの情報を格納　
    @addr[@level] = @localAddr
    @localAddr = firstAddr    #　新しいブロックの最初の変数の番地　
    @level += 1        #　新しいブロックのレベル　
  end

  def blockEnd        #　ブロックの終りで呼ばれる　
    if (@printTable)
      print("\n ******** Symbol Table of level " + @level.to_s + " ********\n")
      start = (@level == 0)? 1 : @index[@level-1] + 1
      start.upto(@tIndex) {|i| print(@nameTable[i].to_s+"\n") }
    end
    if (@level == 0) then return end
    @level -= 1
    @tIndex = @index[@level]    #　一つ外側のブロックの情報を回復
    @localAddr = @addr[@level]
  end


  def fPars()          #　現ブロックの関数のパラメタ数を返す　
    if @level == 0 then 0
    else @nameTable[@index[@level-1]].pars
    end
  end


  def enterT(e)      #　名前表に名前を登録　
    @tIndex += 1
#    print("enterT: at "+@tIndex.to_s+" "+e.to_s+"\n")
    if (@tIndex < MAXTABLE)
        @nameTable[@tIndex] = e
    else
      errorF("too many names")
    end
  end

  def enterTfunc(id)    #　名前表に関数名を登録　
    e = TableEfunc.new(id, :_FuncId)
    enterT(e)
    @tfIndex = @tIndex
    return @tIndex
  end

  def enterTpar(id)        #　名前表にパラメタ名を登録　
    e = TableEaddr.new(id, :_ParId, @level, 0)
    enterT(e)
    @nameTable[@tfIndex].pars += 1       #　関数のパラメタ数のカウント　
    return @tIndex
  end

  def endpar          #　パラメタ宣言部の最後で呼ばれる
    pars = @nameTable[@tfIndex].pars
    if (pars == 0)  then return end
    1.upto(pars) {|i|      #　各パラメタの番地を求める　
        @nameTable[@tfIndex+i].relAddr.addr = i-1-pars }
  end

  def enterTconst(id, v)    #　名前表に定数名とその値を登録　
    e = TableEval.new(id, :_ConstId, v)
     enterT(e)
    return @tIndex
  end

  def enterTvar(id)      #　名前表に変数名を登録　
    e = TableEaddr.new(id, :_VarId, @level, @localAddr)
    @localAddr += 1
     enterT(e)
    return @tIndex
  end

  def searchT(id, k)    #　名前idの名前表の位置を返す
              #　未宣言の時エラーとする　
    i = @tIndex
    @nameTable[0] = TableE.new(id)      #　番兵をたてる　
    while( id != @nameTable[i].name ) do
        i -= 1
    end
    if  i > 0              #　名前があった　
        return i
    else               #　名前がなかった　
        errorType("undef", $token)
        if k == :_VarId
            return enterTvar(id)   #　変数の時は仮登録　
        else
            return 0
        end
    end
  end

  def kindT(i)        #　名前表[i]の種類を返す　
    @nameTable[i].kind
  end

  def relAddrT(i)
    if @nameTable[i].is_a? TableEaddr
       @nameTable[i].relAddr
    else
       RelAddr.new(0, 0)
    end
  end

  def funcNameT(i)
    @nameTable[i].name
  end


  def val(ti)          #　名前表[ti]のvalueを返す　
    @nameTable[ti].value
  end

  def pars(ti)        #　名前表[ti]の関数のパラメタ数を返す　
    @nameTable[ti].pars
  end

  def frameL()        #　そのブロックで実行時に必要とするメモリー容量
#    printf("frameL()=%d\n",@localAddr)
    return @localAddr
  end

end
