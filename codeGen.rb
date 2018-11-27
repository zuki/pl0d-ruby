$cIndex = -1			#　最後に生成した命令語のインデックス
$labelCount = 0
$lastIsRet = false

def newLabel
  $labelCount += 1
  "L_" + $labelCount.to_s
end

def genCodeL(label)
   $Fobj.print(label.to_s+":\n")
end

def genCode(opCode, labelAddr)
  $Fobj.print("\t"+opCode.to_s+", "+labelAddr.to_s+"\n")
  $lastIsRet = false
end

def genCodeT(opCode, index) #　命令語の生成、アドレスは名前表から
  relAddr = $table.relAddrT(index)
  $Fobj.print("\t"+opCode.to_s+", "+relAddr.to_s+"\n")
  $lastIsRet = false
end

def genCodeF(opCode, index) #　命令語の生成、アドレスは名前表から関数名
  name = $table.funcNameT(index)
  $Fobj.print("\t"+opCode.to_s+", "+name.to_s+"\n")
  $lastIsRet = false
end

def genCodeR()				   #　ret命令語の生成　
  if  $lastIsRet then return end    #　直前がretなら生成せず　
  $Fobj.print("\tret,"+$table.level.to_s+","+$table.fPars.to_s+"\n")
  $lastIsRet = true
end

