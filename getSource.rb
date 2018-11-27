
INSERT_C = "#0000FF"  # 挿入文字の色
DELETE_C = "#FF0000"  # 削除文字の色
TYPE_C = "#00FF00"  # タイプエラー文字の色

TAB = 4
MAXNUM = 14
MAXNAME = 128
MAXERROR = 30

FIRSTADDR = 2  # 各ブロックの最初の変数のアドレス
MINERROR = 3   # エラーがこれ以下なら実行

def openSource(sourceFileName)
  $Fsource = File.open(sourceFileName, "r")
  $Fhtml = File.open(sourceFileName+".html", "w")
  $Fobj = File.open(sourceFileName+".asm", "w")
end

def closeSource()
  $Fsource.close
  $Fhtml.close
  $Fobj.close
end

def errorNoCheck     # エラーの個数のカウント、多すぎたら終わり
  $errorNo += 1
  if $errorNo > MAXERROR
    $Fhtml.printf("too many errors\n</PRE>\n</BODY>\n</HTML>\n")
    printf("abort compilation\n")
    exit 1
  end
end


def errorMessage(m)  # エラーメッセージを.htmlファイルに出力
  $Fhtml.printf( "<FONT COLOR=%s>%s</FONT>", TYPE_C, m)
  errorNoCheck
end


def errorF(m)        # エラーメッセージを出力し、コンパイル終了
  errorMessage(m)
  $Fhtml.printf( "fatal errors\n</PRE>\n</BODY>\n</HTML>\n")
  print("abort compilation\n")
end

def errorInsert(s)   # s: key symbol の Stringを.htmlファイルに挿入
  $Fhtml.printf("<FONT COLOR=%s><b>%s</b></FONT>", INSERT_C, s.to_s)
  errorNoCheck
end

def errorMissingId   # 名前がないとのメッセージを.htmlファイルに挿入
  $Fhtml.printf("<FONT COLOR=%s>Id</FONT>", INSERT_C)
  errorNoCheck
end

def errorMissingOp   # 演算子がないとのメッセージを.htmlファイルに挿入
  $Fhtml.printf("<FONT COLOR=%s>@</FONT>", INSERT_C)
  errorNoCheck
end

def errorType(m, t)  # 型エラーを.htmlファイルに出力
  printSpaces(t)
  $Fhtml.printf("<FONT COLOR=%s>%s</FONT>", TYPE_C, m)
  case t.kind
  when :_VarId, :_UserId
   $Fhtml.printf("%s", t.symbol.to_s)
  when :_FuncId, :_ParId
   $Fhtml.printf("<i>%s</i>", t.symbol.to_s)
  when :_ConstId
   $Fhtml.printf("<tt>%s</tt>", t.symbol.to_s)
  end
  t.printed = true
  errorNoCheck
end

def printSpaces(t)   # t の前の空白や改行の印字
  cr = t.cr
  while cr > 0
    $Fhtml.printf("\n"); cr -= 1
  end
  spaces = t.spaces
  while spaces > 0
    $Fhtml.printf(" "); spaces -= 1
  end
end

def errorDelete(t)   # 今読んだトークンを読み捨てる
  printSpaces(t)
  t.printed = true;
  case t.kind
  when :_KeyWd               # 予約語
    $Fhtml.printf("<FONT COLOR=%s><b>%s</b></FONT>", DELETE_C, t.symbol.to_s)
  when :_KeySym              # 演算子か区切り記号
    $Fhtml.printf("<FONT COLOR=%s>%s</FONT>", DELETE_C, t.symbol.to_s)
  when :_UserId              # Identfier
    $Fhtml.printf("<FONT COLOR=%s>%s</FONT>", DELETE_C, t.symbol.to_s)
  when :_Num                 # Num
    $Fhtml.printf("<FONT COLOR=%s>%d</FONT>", DELETE_C, t.value)
  end
end


class Token
  # @kind  :_KeyWd, :_KeySym, :_UserId (:_FuncId, :_ParId, :_VarId), :_Num,
  # @value
  # @symbol
  # @spaces
  # @cr
  # @printed
  attr_reader :kind, :value, :symbol, :spaces, :cr, :printed
  attr_writer :kind, :printed

  def initialize(sp, c, p, k, sy, v)
    @spaces, @cr, @printed = sp, c, p
    @kind, @symbol, @value = k, sy, v
  end

  def to_s
    @symbol.to_s
  end

  def to_string
    pre = if @kind == :_Num then @value.to_s else @symbol.to_s end
    pre +" "+@kind.to_s+" spaces:"+@spaces.to_s+",cr:"+@cr.to_s+",printed:"+@printed.to_s+"\n"
  end
end

def nextChar        #    次の１文字を返す関数
  if $lineIndex == -1
    if ($line = $Fsource.gets) != nil
      $lineIndex = 0
    else
      errorF("end of file\n")    # end of fileならコンパイル終了
    end
  end
     ch = $line[$lineIndex].ord; $lineIndex += 1
  if $lineIndex >= $line.size   #    chに次の１文字
    $lineIndex = -1;    #    それが改行文字なら次の行の入力準備
    return 0x0a;      #    文字としては改行文字を返す
  end
  return ch;
end

def nextToken
  if $cToken != nil then printToken($cToken) end      #    前のトークンを印字
  spaces = 0; cr = 0;
  loop do        #    次のトークンまでの空白や改行をカウント
    if $ch == " ".ord
      spaces += 1
    elsif  $ch == 0x09
      spaces += TAB
    elsif $ch == 0x0a
      spaces = 0;  cr += 1
    elsif $ch == 0x0d
             # print("carriage return\n")
    else break
         end
    $ch = nextChar
  end
  case $charClassT[$ch]
  when :letter then        # identifier
         i = 0; ident = String.new
    while ( $charClassT[$ch] == :letter or $charClassT[$ch] == :digit ) do
      if (i < MAXNAME)
        ident << $ch.chr
              end
      i += 1; $ch = nextChar
    end
    if i >= MAXNAME
      errorMessage("too long")
      i = MAXNAME - 1
    end
         ident  = ident.to_sym
         case ident
         when :begin,:end,:if,:then,:while,:do,:return,:function,:var,:const,:odd,:write,:writeln
      temp = Token.new(spaces, cr, false, :_KeyWd, ident, 0)
    else # ident == _UserId    #    ユーザの宣言した名前の場合
             temp = Token.new(spaces, cr, false, :_UserId, ident, 0)
         end
  when :digit            # number
    num = 0; i = 0
         while $charClassT[$ch] == :digit do
      num = 10*num+($ch-'0'.ord)
      i += 1; $ch = nextChar
    end
        if i > MAXNUM
            errorMessage("too large")
         end
         temp = Token.new(spaces, cr, false, :_Num, nil, num)
  when :":"
    if ($ch = nextChar) == '='.ord   #    ":="
      $ch = nextChar
              temp = Token.new(spaces, cr, false, :_KeySym, :":=", 0)
    else
              temp = Token.new(spaces, cr, false, nil, :"nil", 0)
    end
  when :"<"
    if ($ch = nextChar) == '='.ord   #    "<="
      $ch = nextChar
              temp = Token.new(spaces, cr, false, :_KeySym, :"<=", 0)
    elsif $ch == '>'.ord  #    "<>"
      $ch = nextChar
              temp = Token.new(spaces, cr, false, :_KeySym, :"<>", 0)
    else
              temp = Token.new(spaces, cr, false, :_KeySym, :"<", 0)
    end
  when :">"
    if ($ch = nextChar) == '='.ord   #    ">="
      $ch = nextChar
              temp = Token.new(spaces, cr, false, :_KeySym, :">=", 0)
    else
              temp = Token.new(spaces, cr, false, :_KeySym, :">", 0)
    end
  else
              temp = Token.new(spaces, cr, false, :_KeySym, $ch.chr.to_sym, 0)
    $ch = nextChar
  end
  $cToken = temp;
#    print(temp.to_string)
  return temp
end

def isKeyWd(k)
  case k
  when :begin,:end,:if,:then,:while,:do,:return,:function,:var,:const,:odd,:write,:writeln
     true
  else
     false
  end
end

def isKeySym(k)
  case k
  when :begin,:end,:if,:then,:while,:do,:return,:function,:var,:const,:odd,:write,:writeln
     false
  else
     true
  end
end

def checkGet(t, s)      #    t: Tolen, s: t.symbol のチェック
  #    t.symbol == s なら、次のトークンを読んで返す
  #    t.symbol != s ならエラーメッセージを出し、t と s が共に記号、または予約語なら
  #    t を捨て、次のトークンを読んで返す（ t を s で置き換えたことになる）
  #    それ以外の場合、s を挿入したことにして、t を返す
  if t.symbol == s
      return nextToken  end
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
  if (t.printed) then return end
  t.printed = true
  printSpaces(t)        #    トークンの前の空白や改行印字
    case t.kind
  when :_KeyWd                  #    予約語
    $Fhtml.printf("<b>%s</b>", t.symbol.to_s)
  when :_KeySym                     #    演算子か区切り記号
    $Fhtml.printf("%s", t.symbol.to_s)
  when :_VarId                 #    Var Identfier
    $Fhtml.printf("%s", t.symbol.to_s)
  when :_ParId                 #    Par Identfier
    $Fhtml.printf("<i>%s</i>", t.symbol.to_s)
  when :_FuncId               #    Func Identfier
    $Fhtml.printf("<i>%s</i>", t.symbol.to_s)
  when :_ConstId               #    Constar Identfier
    $Fhtml.printf("<tt>%s</tt>", t.symbol.to_s)
  when :_Num                 #    Num
    $Fhtml.printf("%d", t.value)
    end
end



def initCharClassT
  $charClassT = Array.new(256, :other)
  ("0".ord.."9".ord).each {|i| $charClassT[i] = :digit}
     ("A".ord.."Z".ord).each {|i| $charClassT[i] = :letter}
     ("a".ord.."z".ord).each {|i| $charClassT[i] = :letter}
  $charClassT["+".ord] = :"+"; $charClassT["-".ord] = :"-"
  $charClassT["*".ord] = :"*"; $charClassT["/".ord] = :"/"
  $charClassT["(".ord] = :"("; $charClassT[")".ord] = :")"
  $charClassT["=".ord] = :"="; $charClassT["<".ord] = :"<"
  $charClassT[">".ord] = :">"; $charClassT[",".ord] = :","
  $charClassT[".".ord] = :"."; $charClassT[";".ord] = :";"
  $charClassT[":".ord] = :":"
end

def initSource
    $errorNo = 0        # エラーの個数
    $lineIndex = -1      #    初期設定
  $ch = 0x0a        #    改行文字
  $cToken = nil
  initCharClassT
  $Fhtml.printf("<HTML>\n")   #    htmlコマンド
  $Fhtml.printf("<HEAD>\n<TITLE>compiled source program</TITLE>\n</HEAD>\n")
  $Fhtml.printf("<BODY>\n<PRE>\n")
end

def finalSource
  if $token.symbol == :"."
    printToken($token)
  else
    errorInsert(:".")
    end
  $Fhtml.printf("\n</PRE>\n</BODY>\n</HTML>\n")
end

def errorN
  $errorNo
end
