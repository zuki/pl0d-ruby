module PL0
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

  class TableE         # 名前表のエントリーの基本の型
  #  @kind;                            # 名前の種類
  #  @name;                            # 名前のつづり
    attr_reader :name, :kind
    def initialize(id, kind)
       @name = id
       @kind = kind
    end
    def to_s()
      @name.to_s + ":" + @kind.to_s
    end
  end

  class TableEval < TableE
  #  @value;                           # 定数の場合：値
    attr_reader :value
    def initialize(id, k, v)
      super(id, k)
      @value = v
    end
    def to_s()
      super() + ":" + @value.to_s;
    end
  end

  class TableEaddr < TableE
  #  @relAddr                          # 変数、パラメタのアドレス
    attr_accessor :relAddr
    def initialize(id, k, addr)
      super(id, k)
      @relAddr = addr
    end
    def to_s
      super.to_s + ":" + @relAddr.to_s
    end
  end

  class TableEfunc < TableE
  #  @pars                             # 関数の場合：パラメタ数
    attr_accessor :relAddr, :pars
    def initialize(id, k, addr)
      super(id, k)
      @relAddr = addr
      @pars = 0
    end
    def to_s
      super.to_s + ":" + @pars.to_s + " params"
    end
  end

  class Table
    MAXTABLE = 100                     # 名前表の最大長さ
    MAXLEVEL =   5                     #  ブロックの最大レベル
    def initialize(printTable)
      @printTable = printTable
      @nameTable = Array.new(MAXTABLE) # 名前表
      @tIndex = 0                      # 名前表のインデックス
      @level = -1                      # 現在のブロックレベル
      @index = Array.new(MAXLEVEL)     # index[i]にはブロックレベルiの最後のインデックス
      @addr  = Array.new(MAXLEVEL)     # addr[i]にはブロックレベルiの最後の変数の番地
      @localAddr = 0                   # 現在のブロックの最後の変数の番地
      @tfIndex = -1                    # 関数名の名前表でのインデックス
    end

    def blockBegin(firstAddr)
      if @level == -1                  # 主ブロックの時、初期設定
          @localAddr = firstAddr
          @tIndex = 0
          @level += 1
          return
      end
      if @level == MAXLEVEL - 1
        raise "too many nested blocks"
      end
      @index[@level] = @tIndex         # 今までのブロックの情報を格納
      @addr[@level] = @localAddr
      @localAddr = firstAddr           # 新しいブロックの最初の変数の番地
      @level += 1                      # 新しいブロックのレベル
    end

    def blockEnd       # ブロックの終りで呼ばれる
      if (@printTable)
        print("\n******** Symbol Table of level " + @level.to_s + " ********\n")
        start = (@level == 0) ? 1 : @index[@level-1] + 1
        start.upto(@tIndex) {|i| print(@nameTable[i].to_s+"\n") }
      end
      return if @level == 0
      @level -= 1
      @tIndex = @index[@level]         # 一つ外側のブロックの情報を回復
      @localAddr = @addr[@level]
    end

    def bLevel       # 現在のレベルを返す
      return @level
    end

    def fPars()      # 現ブロックの関数のパラメタ数を返す
      @level == 0 ? 0 : @nameTable[@index[@level-1]].pars
    end

    def enterT(e)    # 名前表に名前を登録
  #    print("enterT: at "+@tIndex.to_s+" "+e.to_s+"\n")
      if (@tIndex < MAXTABLE)
        @tIndex += 1
        @nameTable[@tIndex] = e
      else
        raise "too many names"
      end
    end

    def enterTfunc(id, v)    # 名前表に関数名と先頭番地を登録
      e = TableEfunc.new(id, :_FuncId, RelAddr.new(@level, v))
      enterT(e)
      @tfIndex = @tIndex
      return @tIndex
    end

    def enterTpar(id)  # 名前表にパラメタ名を登録
      e = TableEaddr.new(id, :_ParId, RelAddr.new(@level, 0))
      enterT(e)
      @nameTable[@tfIndex].pars += 1       # 関数のパラメタ数のカウント
      return @tIndex
    end

    def enterTconst(id, v)   # 名前表に定数名とその値を登録
      e = TableEval.new(id, :_ConstId, v)
      enterT(e)
      return @tIndex
    end

    def enterTvar(id)  # 名前表に変数名を登録
      e = TableEaddr.new(id, :_VarId, RelAddr.new(@level, @localAddr))
      @localAddr += 1
      enterT(e)
      return @tIndex
    end

    def endpar         # パラメタ宣言部の最後で呼ばれる
      pars = @nameTable[@tfIndex].pars
      return if pars == 0
      1.upto(pars) do |i|      # 各パラメタの番地を求める
        @nameTable[@tfIndex+i].relAddr.addr = i - 1 - pars
      end
    end

    def changeV(i, newVal)     # 名前表[ti]の値（関数の先頭番地）の変更
      if @nameTable[i]
        @nameTable[i].relAddr.addr = newVal;
      end
    end

    def searchT(id, k) # 名前idの名前表の位置を返す
                                       # 未宣言の時エラーとする
      i = @tIndex
      @nameTable[0] = TableE.new(id, k)  # 番兵をたてる
      while( id != @nameTable[i].name )
        i -= 1
      end
      @nameTable[0] = nil              # 番兵を削除（しないとchangeVでエラー）
      if  i > 0                        # 名前があった
        return i
      else                             # 名前がなかった
        #errorType("undef", $token)
        if k == :_VarId
            return enterTvar(id)       # 変数の時は仮登録
        else
            return 0
        end
      end
    end

    def kindT(i)       # 名前表[i]の種類を返す
      @nameTable[i].kind
    end

    def relAddr(i)    # 名前表[ti]のアドレスを返す
      @nameTable[i].relAddr
    end

    def val(ti)        # 名前表[ti]のvalueを返す
      @nameTable[ti].value
    end

    def pars(ti)       # 名前表[ti]の関数のパラメタ数を返す
      @nameTable[ti].pars
    end

    def frameL         # そのブロックで実行時に必要とするメモリー容量
  #    printf("frameL()=%d\n",@localAddr)
      return @localAddr
    end

    def printNameTable     # nameTableの出力
      printf("\nName table\n")
      0.upto(@tIndex) do |i|
        printf("%3d: ", i)
        printf("%s\n", @nameTable[i].to_s)
      end
    end

  end
end
