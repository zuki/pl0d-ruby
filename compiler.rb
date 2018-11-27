require "getSource"
require "table"
require "codeGen"

def compile(source, printTable)
  openSource source
  printf("start compilation\n")
  initSource            # getSourceの初期設定
  $token = nextToken    # 最初のトークン
  $table = Table.new(printTable)
  $table.blockBegin(FIRSTADDR)    # これ以後の宣言は新しいブロックのもの
  genCode(:jmp, :_main)
  block(:_main)         # 主ブロック名
  finalSource
  closeSource
  i = errorN            # エラーメッセージの個数
  if i >= 1
    printf("\n%d error%s\n", i, (i==1 ? "" : "s"))
  end
  return i < MINERROR  #    エラーメッセージの個数が少ないかどうかの判定
end

def block(func)         # func はこのブロックの関数名
  while true            # 宣言部のコンパイルを繰り返す
    case $token.symbol
    when :const         # 定数宣言部のコンパイル
      $token = nextToken
      constDecl
    when :var           # 変数宣言部のコンパイル
      $token = nextToken
      varDecl
    when :function      # 関数宣言部のコンパイル
      $token = nextToken
      funcDecl
    else                # それ以外なら宣言部は終わり
      break;
    end
  end
  genCodeL(func)
  genCode(:ict, $table.frameL())  # このブロックの実行時の必要記憶域をとる命令
  statement             # このブロックの主文
  genCodeR              # リターン命令
  $table.blockEnd       # ブロックが終ったことをtableに連絡
end

def constDecl      # 定数宣言のコンパイル
  while true
    if $token.kind == :_UserId
      $token.kind = :_ConstId   # 印字のための情報のセット
      temp = $token             # 名前を入れておく
      $token = checkGet(nextToken, :"=")  # 名前の次は"="のはず
      if $token.kind == :_Num
        $table.enterTconst(temp.symbol, $token.value)  # 定数名と値をテーブルに
      else
        errorType("number", $token)
      end
      $token = nextToken
    else
      errorMissingId
    end
    if $token.symbol != :","       # 次がコンマなら定数宣言が続く
      if $token.kind == :UserId    # 次が名前ならコンマを忘れたことにする
        errorInsert(:",")
        next
      else
        break
      end
    end
    $token = nextToken
  end
  $token = checkGet($token, :";")    # 最後は";"のはず
end

def varDecl        # 変数宣言のコンパイル
  while true
    if $token.kind == :_UserId
      $token.kind = :_VarId            # 印字のための情報のセット
      $table.enterTvar($token.symbol)  # 変数名をテーブルに、番地はtableが決める
      $token = nextToken
    else
      errorMissingId
    end
    if $token.symbol != :","           # 次がコンマなら変数宣言が続く
      if $token.kind == :_UserId       # 次が名前ならコンマを忘れたことにする
        errorInsert(:",")
        next
      else
        break
      end
    end
    $token = nextToken
  end
  $token = checkGet($token, :";")      # 最後は";"のはず
end

def funcDecl
  if $token.kind == :_UserId
    $token.kind = :_FuncId               # 印字のための情報のセット
    funcName = $token.symbol
    fIndex = $table.enterTfunc(funcName) # 関数名をテーブルに登録
    $token = checkGet(nextToken(), :"(")
    $table.blockBegin(FIRSTADDR)         # パラメタ名のレベルは関数のブロックと同じ
    while true
      if $token.kind == :_UserId         # パラメタ名がある場合
        $token.kind = :_ParId            # 印字のための情報のセット
        $table.enterTpar($token.symbol)  # パラメタ名をテーブルに登録
        $token = nextToken
      else
        break
      end
      if $token.symbol != :","           # 次がコンマならパラメタ名が続く
        if $token.kind == :_UserId       # 次が名前ならコンマを忘れたことに
          errorInsert(:",")
          next
        else
          break
        end
      else
        $token = nextToken
      end
    end
    $token = checkGet($token, :")")  # 最後は")"のはず
    $table.endpar                    # パラメタ部が終わったことをテーブルに連絡
    if $token.symbol == :";"
      errorDelete($token)
      $token = nextToken
    end
    block(funcName)                  # ブロックのコンパイル、その関数名を渡す
    $token = checkGet($token, :";")  # 最後は";"のはず
  else
    errorMissingId                   # 関数名がない
  end
end

def statement()      # 文のコンパイル
  while true
    if $token.kind == :_UserId       # 代入文のコンパイル
      tIndex = $table.searchT($token.symbol, :_VarId)  # 左辺の変数のインデックス
      $token.kind = k = $table.kindT(tIndex) # 印字のための情報のセット
      if (k != :_VarId && k != :_ParId)      # 変数名かパラメタ名のはず
        errorType("var/par", $token)
      end
      $token = checkGet(nextToken(), :":=")  # ":="のはず
      expression                             # 式のコンパイル
      genCodeT(:sto, tIndex)                 # 左辺への代入命令
      return
    end

    case $token.symbol
    when :if                         # if文のコンパイル
      $token = nextToken
      condition                              # 条件式のコンパイル
      $token = checkGet($token, :then)       # then"のはず
      backP = newLabel
      genCode(:jpc, backP)                   # jpc命令
      statement                              # 文のコンパイル
      genCodeL(backP)                        # 上のjpc命令へのバックパッチに相当
      return
    when :return                     # return文のコンパイル
      $token = nextToken
      expression                             # 式のコンパイル
      genCodeR                               # ret命令
      return
    when :begin                      # begin . . end文のコンパイル
      $token = nextToken
      while true
        statement                            # 文のコンパイル
        while true
          if $token.symbol == :";"           # 次が";"なら文が続く
            $token = nextToken
            break
          end
          if $token.symbol == :end           # 次がendなら終り
            $token = nextToken
            return
          end
          if isStBeginKey($token)            # 次が文の先頭記号なら
            errorInsert(:";")                # ";"を忘れたことにする
            break
          end
          errorDelete($token)                # それ以外ならエラーとして読み捨てる
          $token = nextToken
        end
      end
    when :while                      # while文のコンパイル
      $token = nextToken
      backP2 = newLabel                      # while文の最後のjmp命令の飛び先
      genCodeL(backP2)
      condition                              # 条件式のコンパイル
      $token = checkGet($token, :do)         # "do"のはず
      backP =  newLabel
      genCode(:jpc, backP)                   # 条件式が偽のとき飛び出すjpc命令
      statement                              # 文のコンパイル
      genCode(:jmp, backP2)                  # while文の先頭へのジャンプ命令
      genCodeL(backP)                        # 偽のとき飛び出すjpc命令へのバックパッチに相当
      return
    when :write                      # write文のコンパイル
      $token = nextToken
      expression                             # 式のコンパイル
      genCode(:opr, :wrt)                    # その値を出力するwrt命令
      return
    when :writeln                    # writeln文のコンパイル
      $token = nextToken
      genCode(:opr, :wrl)                    # 改行を出力するwrl命令
      return
    when :end, :";"                  # 空文を読んだことにして終り
      return
    else                             # 文の先頭のキーまで読み捨てる
      errorDelete($token)                    # 今読んだトークンを読み捨てる
      $token = nextToken
      next
    end
  end
end

def expression       # 式のコンパイル
  k = $token.symbol
  if (k == :"+" || k == :"-")
    $token = nextToken
    term
    genCode(:opr, :neg) if k == :"-"
  else
    term
  end
  k = $token.symbol
  while (k == :"+" || k == :"-")
    $token = nextToken
    term
    if k == :"-"
      genCode(:opr, :sub)
    else
      genCode(:opr, :add)
    end
    k = $token.symbol
  end
end

def term()           # 式の項のコンパイル
  factor()
  k = $token.symbol
  while (k == :"*" || k == :"/")
    $token = nextToken()
    factor()
    if (k == :"*")
      genCode(:opr, :mul)
    else
      genCode(:opr, :div)
    end
    k = $token.symbol
  end
end

def factor           # 式の因子のコンパイル
  if $token.kind == :_UserId
    tIndex = $table.searchT($token.symbol, :_VarId)
    $token.kind = k = $table.kindT(tIndex)   # 印字のための情報のセット
    case k
    when :_VarId, :_ParId                    # 変数名かパラメタ名
      genCodeT(:lod, tIndex)
      $token = nextToken
    when :_ConstId                           # 定数名
      genCode(:lit, $table.val(tIndex))
      $token = nextToken
    when :_FuncId                            # 関数呼び出し
      $token = nextToken
      if $token.symbol == :"("
        i=0                                  # iは実引数の個数
        $token = nextToken
        if $token.symbol != :")"
          while true
            expression; i += 1               # 実引数のコンパイル
            if $token.symbol == :","         # 次がコンマなら実引数が続く
              $token = nextToken
              next
            end
            $token = checkGet($token, :")")
            break
          end
        else
          $token = nextToken
        end
        if $table.pars(tIndex) != i
          errorMessage("\\#par")             # pars(tIndex)は仮引数の個数
        end
      else
        errorInsert(:"(")
        errorInsert(:")")
      end
      genCodeF(:cal, tIndex)                 # call命令
    end
  elsif $token.kind == :_Num                 # 定数
    genCode(:lit, $token.value)
    $token = nextToken
  elsif $token.symbol == :"("                # 「(」「因子」「)」
    $token = nextToken
    expression
    $token = checkGet($token, :")")
  end
  case $token.kind                           # 因子の後がまた因子ならエラー
  when :_UserId, :_Num
    errorMissingOp
    factor
  when :_KeySym
    if $token.symbol == :"("
        errorMissingOp
        factor
    end
  else
    return
  end
end

def condition        # 条件式のコンパイル
  if $token.symbol == :odd
    $token = nextToken
    expression
    genCode(:opr, :odd)
  else
    expression
    k = $token.symbol
    case k
    when :"=", :"<", :">", :"<>", :"<=", :">="
       # do nothing
    else
      errorType("rel-op", $token)
    end
    $token = nextToken
    expression
    case k
    when :"="  then  genCode(:opr, :eq)
    when :"<"  then  genCode(:opr, :ls)
    when :">"  then  genCode(:opr, :gr)
    when :"<>" then  genCode(:opr, :neq)
    when :"<=" then  genCode(:opr, :lseq)
    when :">=" then  genCode(:opr, :greq)
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
