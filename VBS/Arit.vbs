
on error resume next
dim NUMBER,FACTOR,PERCENT,LOG_FIX,RESULT
NUMBER = CDbl(WScript.Arguments.Item(0))
FACTOR = CDbl(WScript.Arguments.Item(1))
PERCENT = CDbl(WScript.Arguments.Item(2))
LOG_FIX = CDbl(WScript.Arguments.Item(3))
RESULT = Round(NUMBER*FACTOR*PERCENT*LOG_FIX)
WScript.Echo RESULT