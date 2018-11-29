module PL0
  class Token
    # @kind  :_KeyWd, :_KeySym, :_UserId (:_FuncId, :_ParId, :_VarId), :_Num,
    # @value                 # トークン値
    # @symbol                # トークン名
    # @spaces                # そのトークンの前のスペースの個数
    # @cr                    # その前のCRの個数
    # @printed               # トークンは印字済みか
    attr_accessor :kind, :printed
    attr_reader :value, :symbol, :spaces, :cr

    def initialize(sp, c, p, k, sy, v)
      @spaces, @cr, @printed = sp, c, p
      @kind, @symbol, @value = k, sy, v
    end

    def to_s
      @symbol.to_s
    end

    def to_string
      pre = if @kind == :_Num then @value.to_s else @symbol.to_s end
      pre += " "+@kind.to_s+" spaces:"+@spaces.to_s+",cr:"+@cr.to_s+",printed:"+@printed.to_s+"\n"
    end
  end

  class Lexer
    INSERT_C = "#0000FF"   # 挿入文字の色
    DELETE_C = "#FF0000"   # 削除文字の色
    TYPE_C = "#00FF00"     # タイプエラー文字の色

    TAB = 4                # タブのスペース
    MAXNUM = 14            # 定数の最大桁数
    MAXERROR = 30          # これ以上のエラーがあったら終り

    FIRSTADDR = 2  # 各ブロックの最初の変数のアドレス
    MINERROR = 3   # エラーがこれ以下なら実行

    # @ctoken      一つ前のトークン

    def initialize(sourceFileName)
      @source = sourceFileName
    end

    def openSource
      @Fsource = File.open(@source, "r")
      @Fhtml = File.open(@source+".html", "w")
    end

    def closeSource
      @Fsource.close
      @Fhtml.close
    end

    def errorNoCheck     # エラーの個数のカウント、多すぎたら終わり
      @errorNo += 1
      if @errorNo > MAXERROR
        @Fhtml.printf("too many errors\n</PRE>\n</BODY>\n</HTML>\n")
        raise "abort compilation\n"
      end
    end

    def errorMessage(m)  # エラーメッセージを.htmlファイルに出力
      @Fhtml.printf( "<FONT COLOR=%s>%s</FONT>", TYPE_C, m)
      errorNoCheck
    end

    def errorF(m)        # エラーメッセージを出力し、コンパイル終了
      errorMessage(m)
      @Fhtml.printf( "fatal errors\n</PRE>\n</BODY>\n</HTML>\n")
      raise "abort compilation\n"
    end

    def errorInsert(s)   # s: key symbol の Stringを.htmlファイルに挿入
      @Fhtml.printf("<FONT COLOR=%s><b>%s</b></FONT>", INSERT_C, s.to_s)
      errorNoCheck
    end

    def errorMissingId   # 名前がないとのメッセージを.htmlファイルに挿入
      @Fhtml.printf("<FONT COLOR=%s>Id</FONT>", INSERT_C)
      errorNoCheck
    end

    def errorMissingOp   # 演算子がないとのメッセージを.htmlファイルに挿入
      @Fhtml.printf("<FONT COLOR=%s>@</FONT>", INSERT_C)
      errorNoCheck
    end

    def errorType(m, t)  # 型エラーを.htmlファイルに出力
      printSpaces(t)
      @Fhtml.printf("<FONT COLOR=%s>%s</FONT>", TYPE_C, m)
      case t.kind
      when :_VarId, :_UserId
       @Fhtml.printf("%s", t.symbol.to_s)
      when :_FuncId, :_ParId
       @Fhtml.printf("<i>%s</i>", t.symbol.to_s)
      when :_ConstId
       @Fhtml.printf("<tt>%s</tt>", t.symbol.to_s)
      end
      errorNoCheck
    end

    def printSpaces(t)   # t の前の空白や改行の印字
      @Fhtml.printf("<br/>" * t.cr) if t.cr > 0
      @Fhtml.printf("&nbsp\;" * t.spaces) if t.spaces > 0
    end

    def errorDelete(t)   # 今読んだトークンを読み捨てる
      printSpaces(t)
      t.printed = true;
      case t.kind
      when :_KeyWd               # 予約語
        @Fhtml.printf("<FONT COLOR=%s><b>%s</b></FONT>", DELETE_C, t.symbol.to_s)
      when :_KeySym              # 演算子か区切り記号
        @Fhtml.printf("<FONT COLOR=%s>%s</FONT>", DELETE_C, t.symbol.to_s)
      when :_UserId              # Identfier
        @Fhtml.printf("<FONT COLOR=%s>%s</FONT>", DELETE_C, t.symbol.to_s)
      when :_Num                 # Num
        @Fhtml.printf("<FONT COLOR=%s>%d</FONT>", DELETE_C, t.value)
      end
    end

    def nextChar        #    次の１文字を返す関数
      if @lineIndex == -1
        if @line = @Fsource.gets
          @lineNo += 1
          @lineIndex = 0
        else
          errorF("end of file\n")    # end of fileならコンパイル終了
        end
      end
      ch = @line[@lineIndex]
      @lineIndex += 1
      if @lineIndex >= @line.size    # 1行を使い終わった
        @lineIndex = -1;             # 次の行の入力準備
        return "\n";                 # 文字としては改行文字を返す
      end
      return ch;
    end

    def nextToken
      printToken(@cToken) if @cToken # 前のトークンを印字
      spaces = 0; cr = 0;
      while true                     # 空白や改行をカウント
        if @ch == " "
          spaces += 1
        elsif  @ch == "\t"
          spaces += TAB
        elsif @ch == "\n"
          spaces = 0;  cr += 1
        elsif @ch == "\r"
          # print("carriage return\n")
        else
          break
        end
        @ch = nextChar
      end
      case @charClassT[@ch.ord]
      when :letter           # identifier
        ident = ""
        begin
          ident << @ch
          @ch = nextChar
        end while ( @charClassT[@ch.ord] == :letter or @charClassT[@ch.ord] == :digit )
        ident = ident.downcase.to_sym
        case ident
        when :begin, :end, :if, :then, :while, :do, :return,
             :function, :var, :const, :odd, :write, :writeln
          temp = Token.new(spaces, cr, false, :_KeyWd, ident, 0)
        else       # ident == _UserId: ユーザの宣言した名前の場合
          temp = Token.new(spaces, cr, false, :_UserId, ident, 0)
        end
      when :digit            # number
        num = 0; i = 0
        begin
          num = 10 * num + @ch.to_i
          i += 1
          @ch = nextChar
        end while @charClassT[@ch.ord] == :digit
        errorMessage("too large") if i > MAXNUM
        temp = Token.new(spaces, cr, false, :_Num, nil, num)
      when :":"
        @ch = nextChar
        if @ch == '='                # ":="
          @ch = nextChar
          temp = Token.new(spaces, cr, false, :_KeySym, :":=", 0)
        else
          temp = Token.new(spaces, cr, false, nil, :"nil", 0)
        end
      when :"<"
        @ch = nextChar
        if @ch == '='                #    "<="
          @ch = nextChar
          temp = Token.new(spaces, cr, false, :_KeySym, :"<=", 0)
        elsif @ch == '>'             #    "<>"
          @ch = nextChar
          temp = Token.new(spaces, cr, false, :_KeySym, :"<>", 0)
        else
          temp = Token.new(spaces, cr, false, :_KeySym, :"<", 0)
        end
      when :">"
        @ch = nextChar
        if @ch == '='                # ">="
          @ch = nextChar
          temp = Token.new(spaces, cr, false, :_KeySym, :">=", 0)
        else
          temp = Token.new(spaces, cr, false, :_KeySym, :">", 0)
        end
      else
        temp = Token.new(spaces, cr, false, :_KeySym, @ch.to_sym, 0)
        @ch = nextChar
      end
      @cToken = temp;
    #  print(temp.to_string)
      return temp
    end

    def isKeyWd(k)           # 識別子は予約語か
      case k
      when :begin, :end, :if, :then, :while, :do, :return,
           :function, :var, :const, :odd, :write, :writeln
         true
      else
         false
      end
    end

    def isKeySym(k)          # 識別子はユーザ指定の識別子か
      !isKeyWd(k)
    end

    def checkGet(t, s)      #    t: Tolen, s: t.symbol のチェック
      #    t.symbol == s なら、次のトークンを読んで返す
      #    t.symbol != s ならエラーメッセージを出し、t と s が共に記号、または予約語なら
      #    t を捨て、次のトークンを読んで返す（ t を s で置き換えたことになる）
      #    それ以外の場合、s を挿入したことにして、t を返す
      return nextToken if t.symbol == s
      if ((isKeyWd(s) && t.kind == :_KeyWd) ||
        (isKeySym(s) && t.kind == :_KeySym))
        errorDelete(t)
        errorInsert(s)
        return nextToken
      end
      errorInsert(s)
      return t
    end

    def printToken(t)        #    トークン t の印字
      return if t.printed
      t.printed = true
      printSpaces(t)        #    トークンの前の空白や改行印字
      case t.kind
      when :_KeyWd                   # 予約語
        @Fhtml.printf("<b>%s</b>", t.symbol.to_s)
      when :_KeySym                  # 演算子か区切り記号
        @Fhtml.printf("%s", t.symbol.to_s)
      when :_VarId                   # Var Identfier
        @Fhtml.printf("%s", t.symbol.to_s)
      when :_ParId                   # Par Identfier
        @Fhtml.printf("<i>%s</i>", t.symbol.to_s)
      when :_FuncId                  # Func Identfier
        @Fhtml.printf("<i>%s</i>", t.symbol.to_s)
      when :_ConstId                 # Constar Identfier
        @Fhtml.printf("<tt>%s</tt>", t.symbol.to_s)
      when :_Num                     # Num
        @Fhtml.printf("%d", t.value)
      end
    end

    def initCharClassT
      @charClassT = Array.new(256, :other)
      ("0".ord.."9".ord).each {|i| @charClassT[i] = :digit}
      ("A".ord.."Z".ord).each {|i| @charClassT[i] = :letter}
      ("a".ord.."z".ord).each {|i| @charClassT[i] = :letter}
      @charClassT["+".ord] = :"+"; @charClassT["-".ord] = :"-"
      @charClassT["*".ord] = :"*"; @charClassT["/".ord] = :"/"
      @charClassT["(".ord] = :"("; @charClassT[")".ord] = :")"
      @charClassT["=".ord] = :"="; @charClassT["<".ord] = :"<"
      @charClassT[">".ord] = :">"; @charClassT[",".ord] = :","
      @charClassT[".".ord] = :"."; @charClassT[";".ord] = :";"
      @charClassT[":".ord] = :":"
    end

    def initSource
      @errorNo = 0           # エラーの個数
      @lineNo = 0            # ソース行
      @lineIndex = -1        # ソース行内の文字位置
      @ch = "\n"             # ソースの現在位置の文字
      @cToken = nil          # カレントトークン
      initCharClassT
      @Fhtml.printf("<HTML>\n")   # htmlコマンド
      @Fhtml.printf("<HEAD>\n<TITLE>compiled source program</TITLE>\n</HEAD>\n")
      @Fhtml.printf("<BODY>\n<PRE>\n")
    end

    def finalSource(t)
      if t.symbol == :"."
        printToken(t)
      else
        errorInsert(:".")
        end
      @Fhtml.printf("\n</PRE>\n</BODY>\n</HTML>\n")
    end

    def errorN
      @errorNo
    end
  end
end
