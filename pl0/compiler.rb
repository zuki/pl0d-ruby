module PL0
  class Compiler
    MINERROR  = 3            # エラーがこれ以下なら実行
    FIRSTADDR = 2            # 各ブロックの最初の変数のアドレス

    def initialize(source, params)
      @lexer = Lexer.new(source)
      @table = Table.new(params[:s])
      @codegen = CodeGen.new
      @list_code = params[:l]
    end

    def parse
      @lexer.openSource
      printf("start compilation\n")
      @lexer.initSource            # getSourceの初期設定
      @token = @lexer.nextToken(nil)     # 最初のトークン
      @table.blockBegin(FIRSTADDR) # これ以後の宣言は新しいブロックのもの
      block(0)                     # 0 はダミー（主ブロックの関数名はない）
      @lexer.finalSource(@token)
      @lexer.closeSource
      no = Log.errorN           # エラーメッセージの個数
      if no >= 1
        printf("%d error%s\n", no, (no==1 ? "" : "s"))
      end
      return no < MINERROR   # エラーメッセージの個数が少ないかどうかの判定
    end

    def execute
      @codegen.listCode if @list_code
      @codegen.execute
    end

    def block(pIndex)        # pIndex はこのブロックの関数名のインデックス
      backP = @codegen.genCodeV(:jmp, 0)   # 内部関数を飛び越す命令、後でバックパッチ
      while true                     # 宣言部のコンパイルを繰り返す
        case @token.symbol
        when :const                  # 定数宣言部のコンパイル
          @token = @lexer.nextToken(@token)
          constDecl
        when :var                    # 変数宣言部のコンパイル
          @token = @lexer.nextToken(@token)
          varDecl
        when :function               # 関数宣言部のコンパイル
          @token = @lexer.nextToken(@token)
          funcDecl
        else                         # それ以外なら宣言部は終わり
          break;
        end
      end
      @codegen.backPatch(backP)            # 内部関数を飛び越す命令にパッチ
      @table.changeV(pIndex, @codegen.nextCode)  # この関数の開始番地を修正
      @codegen.genCodeV(:ict, @table.frameL)     # このブロックの実行時の必要記憶域をとる命令
      statement                            # このブロックの主文
      @codegen.genCodeR(RelAddr.new(@table.bLevel, @table.fPars))  # リターン命令
      @table.blockEnd                      # ブロックが終ったことをtableに連絡
    end

    def constDecl      # 定数宣言のコンパイル
      while true
        if @token.kind == :_UserId
          @token.kind = :_ConstId   # 印字のための情報のセット
          temp = @token             # 名前を入れておく
          @token = @lexer.checkGet(@lexer.nextToken(@token), :"=") # 名前の次は"="のはず
          if @token.kind == :_Num
            @table.enterTconst(temp.symbol, @token.value)  # 定数名と値をテーブルに
          else
            Log.error("assign not number", @token)
          end
          @token = @lexer.nextToken(@token)
        else
          Log.error("missing const name", @token)
        end
        if @token.symbol != :","       # 次がコンマなら定数宣言が続く
          if @token.kind == :UserId    # 次が名前ならコンマを忘れたことにする
            Log.error("insert ','", @token)
            next
          else
            break
          end
        end
        @token = @lexer.nextToken(@token)
      end
      @token = @lexer.checkGet(@token, :";")    # 最後は";"のはず
    end

    def varDecl        # 変数宣言のコンパイル
      while true
        if @token.kind == :_UserId
          @token.kind = :_VarId            # 印字のための情報のセット
          @table.enterTvar(@token.symbol)  # 変数名をテーブルに、番地はtableが決める
          @token = @lexer.nextToken(@token)
        else
          Log.error("missing var name", @token)
        end
        if @token.symbol != :","           # 次がコンマなら変数宣言が続く
          if @token.kind == :_UserId       # 次が名前ならコンマを忘れたことにする
            Log.error("insert ','", @token)
            next
          else
            break
          end
        end
        @token = @lexer.nextToken(@token)
      end
      @token = @lexer.checkGet(@token, :";")      # 最後は";"のはず
    end

    def funcDecl
      if @token.kind == :_UserId
        @token.kind = :_FuncId               # 印字のための情報のセット
        fIndex = @table.enterTfunc(@token.symbol, @codegen.nextCode)
                   # 関数名をテーブルに登録。
                   # その先頭番地は、まず、次のコードの番地とする
        @token = @lexer.checkGet(@lexer.nextToken(@token), :"(")
        @table.blockBegin(FIRSTADDR)         # パラメタ名のレベルは関数のブロックと同じ
        while true
          if @token.kind == :_UserId         # パラメタ名がある場合
            @token.kind = :_ParId            # 印字のための情報のセット
            @table.enterTpar(@token.symbol)  # パラメタ名をテーブルに登録
            @token = @lexer.nextToken(@token)
          else
            break
          end
          if @token.symbol != :","           # 次がコンマならパラメタ名が続く
            if @token.kind == :_UserId       # 次が名前ならコンマを忘れたことに
              Log.error("insert ','", @token)
              next
            else
              break
            end
          end
          @token = @lexer.nextToken(@token)
        end
        @token = @lexer.checkGet(@token, :")") # 最後は")"のはず
        @table.endpar                # パラメタ部が終わったことをテーブルに連絡
        if @token.symbol == :";"
          Log.error(sprintf("delete token: %s", @token.symbol||@token.value), @token)
          @token = @lexer.nextToken(@token)
        end
        block(fIndex)                # ブロックのコンパイル、その関数名を渡す
        @token = @lexer.checkGet(@token, :";")  # 最後は";"のはず
      else
        Log.error("missing function name", @token)         # 関数名がない
      end
    end

    def statement    # 文のコンパイル
      while true
        if @token.kind == :_UserId       # 代入文のコンパイル
          tIndex = @table.searchT(@token, :_VarId)  # 左辺の変数のインデックス
          @token.kind = k = @table.kindT(tIndex) # 印字のための情報のセット
          if (k != :_VarId && k != :_ParId)      # 変数名かパラメタ名のはず
            Log.error("assign lhs is not var/par", @token)
          end
          @token = @lexer.checkGet(@lexer.nextToken(@token), :":=")  # ":="のはず
          expression                             # 式のコンパイル
          @codegen.genCodeT(:sto, @table.relAddr(tIndex))    # 左辺への代入命令
          return
        end

        case @token.symbol
        when :if                     # if文のコンパイル
          @token = @lexer.nextToken(@token)
          condition                      # 条件式のコンパイル
          @token = @lexer.checkGet(@token, :then)       # thenのはず
          backP = @codegen.genCodeV(:jpc, 0)            # jpc命令
          statement                      # 文のコンパイル
          @codegen.backPatch(backP)      # 上のjpc命令へのバックパッチに相当
          return
        when :return                 # return文のコンパイル
          @token = @lexer.nextToken(@token)
          expression                     # 式のコンパイル
          @codegen.genCodeR(RelAddr.new(@table.bLevel, @table.fPars))   # ret命令
          return
        when :begin                  # begin . . end文のコンパイル
          @token = @lexer.nextToken(@token)
          while true
            statement                    # 文のコンパイル
            while true
              if @token.symbol == :";"   # 次が";"なら文が続く
                @token = @lexer.nextToken(@token)
                break
              end
              if @token.symbol == :end   # 次がendなら終り
                @token = @lexer.nextToken(@token)
                return
              end
              if isStBeginKey(@token)    # 次が文の先頭記号なら
                Log.error("insert ';'", @token.prev) # ";"を忘れたことにする
                break
              end
              Log.error(sprintf("delete '%s' and skip to a new statement", @token.symbol || @token.value), @token)  # それ以外ならエラーとして読み捨てる
              @token = @lexer.nextToken(@token)
            end
          end
        when :while                # while文のコンパイル
          @token = @lexer.nextToken(@token)
          backP2 = @codegen.nextCode     # while文の最後のjmp命令の飛び先
          condition                      # 条件式のコンパイル
          @token = @lexer.checkGet(@token, :do)  # "do"のはず
          backP =  @codegen.genCodeV(:jpc, 0)    # 条件式が偽のとき飛び出すjpc命令
          statement                      # 文のコンパイル
          @codegen.genCodeV(:jmp, backP2)  # while文の先頭へのジャンプ命令
          @codegen.backPatch(backP)      # 偽のとき飛び出すjpc命令へのバックパッチに相当
          return
        when :write                # write文のコンパイル
          @token = @lexer.nextToken(@token)
          expression                     # 式のコンパイル
          @codegen.genCodeO(:wrt)  # その値を出力するwrt命令
          return
        when :writeln              # writeln文のコンパイル
          @token = @lexer.nextToken(@token)
          @codegen.genCodeO(:wrl)        # 改行を出力するwrl命令
          return
        when :end, :";"           # 空文を読んだことにして終り
          return
        else                      # 文の先頭のキーまで読み捨てる
          Log.error(sprintf("delete '%s' and skip to a new statement", @token.symbol||@token.value), @token)  # 今読んだトークンを読み捨てる
          @token = @lexer.nextToken(@token)
        end
      end
    end

    def expression   # 式のコンパイル
      k = @token.symbol
      if (k == :"+" || k == :"-")
        @token = @lexer.nextToken(@token)
        term
        @codegen.genCodeO(:neg) if k == :"-"
      else
        term
      end
      k = @token.symbol
      while (k == :"+" || k == :"-")
        @token = @lexer.nextToken(@token)
        term
        if k == :"-"
          @codegen.genCodeO(:sub)
        else
          @codegen.genCodeO(:add)
        end
        k = @token.symbol
      end
    end

    def term         # 式の項のコンパイル
      factor
      k = @token.symbol
      while (k == :"*" || k == :"/")
        @token = @lexer.nextToken(@token)
        factor
        if (k == :"*")
          @codegen.genCodeO(:mul)
        else
          @codegen.genCodeO(:div)
        end
        k = @token.symbol
      end
    end

    def factor       # 式の因子のコンパイル
      if @token.kind == :_UserId
        tIndex = @table.searchT(@token, :_VarId)
        @token.kind = k = @table.kindT(tIndex)   # 印字のための情報のセット
        case k
        when :_VarId, :_ParId                    # 変数名かパラメタ名
          @codegen.genCodeT(:lod, @table.relAddr(tIndex))
          @token = @lexer.nextToken(@token)
        when :_ConstId                           # 定数名
          @codegen.genCodeV(:lit, @table.val(tIndex))
          @token = @lexer.nextToken(@token)
        when :_FuncId                            # 関数呼び出し
          @token = @lexer.nextToken(@token)
          if @token.symbol == :"("
            i=0                                  # iは実引数の個数
            @token = @lexer.nextToken(@token)
            if @token.symbol != :")"
              while true
                expression; i += 1               # 実引数のコンパイル
                if @token.symbol == :","         # 次がコンマなら実引数が続く
                  @token = @lexer.nextToken(@token)
                  next
                end
                @token = @lexer.checkGet(@token, :")")
                break
              end
            else
              @token = @lexer.nextToken(@token)
            end
            if @table.pars(tIndex) != i
              Log.error("\\#par", @token)        # pars(tIndex)は仮引数の個数
            end
          else
            Log.error("insert '()'", @token)
          end
          @codegen.genCodeT(:cal, @table.relAddr(tIndex))  # call命令
        end
      elsif @token.kind == :_Num                 # 定数
        @codegen.genCodeV(:lit, @token.value)
        @token = @lexer.nextToken(@token)
      elsif @token.symbol == :"("                # 「(」「因子」「)」
        @token = @lexer.nextToken(@token)
        expression
        @token = @lexer.checkGet(@token, :")")
      end
      case @token.kind                           # 因子の後がまた因子ならエラー
      when :_UserId, :_Num
        Log.error(sprintf("factor + id/num '%s': missing opcode", @token.symbol||@token.value), @token)
        factor
      when :_KeySym
        if @token.symbol == :"("
          Log.error("factor + '(': missing opcode", @token)
          factor
        else
          return
        end
      else
        return
      end
    end

    def condition    # 条件式のコンパイル
      if @token.symbol == :odd
        @token = @lexer.nextToken(@token)
        expression
        @codegen.genCodeO(:odd)
      else
        expression
        k = @token.symbol
        case k
        when :"=", :"<", :">", :"<>", :"<=", :">="
           # do nothing
        else
          Log.error("symbol is not an operator", @token)
        end
        @token = @lexer.nextToken(@token)
        expression
        case k
        when :"="  then  @codegen.genCodeO(:eq)
        when :"<"  then  @codegen.genCodeO(:ls)
        when :">"  then  @codegen.genCodeO(:gr)
        when :"<>" then  @codegen.genCodeO(:neq)
        when :"<=" then  @codegen.genCodeO(:lseq)
        when :">=" then  @codegen.genCodeO(:greq)
        end
      end
    end

    def isStBeginKey(t)  # トークンtは文の先頭のキーか？
      case t.symbol
      when :if, :begin, :return, :while, :write, :writeln
        return true
      end
      return false
    end
  end
end
