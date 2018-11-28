module PL0
  class Inst
    # @opCode: 命令語のコード
    #  [:lit, :opr, :lod, :sto, :cal, :ret, :ict, :jmp, :jpc]

    # @addr: PL0::RelAddrのオブジェクト
    #  @addr.level, @addr.addr

    # @value: 値

    # @optr: 演算命令のコード
    #  [:neg, :add, :sub, :mul,  :div,  :odd, :eq,
    #   :ls,  :gr,  :neq, :lseq, :greq, :wrt, :wrl]

    attr_accessor :opCode, :addr, :value, :optr
  end

  class CodeGen
    MAXCODE  =  200      # 目的コードの最大長さ
    MAXMEM   = 2000      # 実行時スタックの最大長さ
    MAXREG   =   20      # 演算レジスタスタックの最大長さ
    MAXLEVEL =    5      # ブロックの最大深さ

    def initialize
      @code = Array.new(MAXCODE)
      @cIndex = -1               # 最後に生成した命令語のインデックス
      @labelCount = 0
      @lastIsRet = false
    end

    def nextCode                 # 次の命令語のアドレスを返す
      @cIndex + 1
    end

    def genCodeV(opCode, v)      # 命令語の生成、アドレス部にv
      checkMax
      @code[@cIndex].opCode = opCode
      @code[@cIndex].value  = v
      @cIndex
    end

    def genCodeT(opCode, reladdr)  # 命令語の生成、アドレスは名前表から
      checkMax
      @code[@cIndex].opCode = opCode
      @code[@cIndex].addr   = reladdr
      @cIndex
    end

    def genCodeO(operator)  # 命令語の生成、アドレス部に演算命令  */
      checkMax
      @code[@cIndex].opCode = :opr
      @code[@cIndex].optr = operator
      @cIndex
    end

    def genCodeR(reladdr)   # ret命令語の生成
      return @cIndex if @code[@cIndex].opCode == :ret # 直前がretなら生成せず
      checkMax
      @code[@cIndex].opCode = :ret
      @code[@cIndex].addr = reladdr
      @cIndex
    end

    def checkMax     # 目的コードのインデックスの増加とチェック
      @cIndex += 1
      if @cIndex < MAXCODE
        @code[@cIndex] = Inst.new
        return
      end
      errorF "too many code"
    end

    def backPatch(i) # 命令語のバックパッチ（次の番地を）
      @code[i].value = @cIndex + 1;
    end

    def listCode     # 命令語のリスティング
      printf("\ncode\n")
      0.upto(@cIndex) do |i|
        printf("%3d: ", i)
        printCode(i)
      end
    end

    def printCode(i)     # 命令語の印字
      printf("%s", @code[i].opCode.to_s)
      case @code[i].opCode
      when :lit, :ict, :jmp, :jpc
        flag = 1
      when :lod, :sto, :cal, :ret
        flag = 2
      when :opr
        flag = 3
      end

      case flag
      when 1
        printf(",%d\n", @code[i].value)
      when 2
        printf(",%d,%d\n", @code[i].addr.level, @code[i].addr.addr)
      when 3
        printf(",%s\n", @code[i].optr,to_s)
      end
    end

    def execute
      stack = Array.new(MAXMEM)        # 実行時スタック
      display = Array.new(MAXLEVEL)    # 現在見える各ブロックの先頭番地のディスプレイ
      printf("\nstart execution\n");
      top = 0                          # 次にスタックに入れる場所
      pc = 0                           # 命令語のカウンタ
      stack[0] = 0                     # calleeで壊すディスプレイの退避場所
      stack[1] = 0                     # callerへの戻り番地
      display[0] = 0                   # 主ブロックの先頭番地は 0
      begin
        inst = @code[pc]               #  これから実行する命令語
        pc += 1
        case inst.opCode
        when :lit
          stack[top] = inst.value
          top += 1
        when :lod
          stack[top] = stack[display[inst.addr.level] + inst.addr.addr]
          top += 1
        when :sto
          top -= 1
          stack[display[inst.addr.level] + inst.addr.addr] = stack[top]
        when :cal
          lev = inst.addr.level + 1    # inst.addr.levelはcalleeの名前のレベル
                                       #  calleeのブロックのレベルlevはそれに＋１したもの
          stack[top] = display[lev]    # display[lev]の退避
          stack[top+1] = pc
          display[lev] = top           # 現在のtopがcalleeのブロックの先頭番地
          pc = inst.addr.addr
        when :ret
          top -= 1
          temp = stack[top]            # スタックのトップにあるものが返す値
          top = display[inst.addr.level]         # topを呼ばれたときの値に戻す
          display[inst.addr.level] = stack[top]  # 壊したディスプレイの回復
          pc = stack[top+1]
          top -= inst.addr.addr        # 実引数の分だけトップを戻す
          stack[top] = temp            # 返す値をスタックのトップへ
          top += 1
        when :ict
          top += inst.value
          if (top >= MAXMEM-MAXREG)
            raise "stack overflow"
          end
        when :jmp
          pc = inst.value
        when :jpc
          top -= 1
          if (stack[top] == 0)
            pc = inst.value
          end
        when :opr
          case inst.optr
          when :neg
            stack[top-1] = -stack[top-1]
          when :add
            top -= 1
            stack[top-1] += stack[top]
          when :sub
            top -= 1
            stack[top-1] -= stack[top]
          when :mul
            top -= 1
            stack[top-1] *= stack[top]
          when :div
            top -= 1
            stack[top-1] /= stack[top]
          when :odd
            stack[top-1] = (stack[top-1] % 2 == 1 ? 1 : 0)
          when :eq
            top -= 1
            stack[top-1] = (stack[top-1] == stack[top] ? 1 : 0)
          when :ls
            top -= 1
            stack[top-1] = (stack[top-1] < stack[top] ? 1 : 0)
          when :gr
            top -= 1
            stack[top-1] = (stack[top-1] > stack[top] ? 1 : 0)
          when :neq
            top -= 1
            stack[top-1] = (stack[top-1] != stack[top] ? 1 : 0)
          when :lseq
            top -= 1
            stack[top-1] = (stack[top-1] <= stack[top] ? 1 : 0)
          when :greq
            top -= 1
            stack[top-1] = (stack[top-1] >= stack[top] ? 1 : 0)
          when :wrt
            top -= 1
            printf("%d ", stack[top])
          when :wrl
            printf("\n")
          end
        end
      end while pc != 0 && @code[pc]
    end
  end
end
