@echo off
Title Suporte - Inilog
color f9
mode 80,10
ren Created byFrancisney Delmondes
ren francisney@inilgog.com.br
ren www.inilog.com
rem @francisneydelmondes @inilog #inilog #francisneydelmondes

cls 

echo -
echo Execute esse script com a impressora desligada!
echo -
net stop spooler
del /q/f/s %systemroot%\system32\spool\PRINTERS\*.*
net start spooler

mshta vbscript:Execute("msgbox ""Comando realizado! Pode ligar a impressora e realizar os testes. https://inilog.com/hesk "":close")
cls
exit
