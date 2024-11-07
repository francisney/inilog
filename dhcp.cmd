@echo off
Title  INILOG - Support
cls
color 79
mode 45,15
rem Script Created by Francisney Delmondes
rem (61)99363-0969
rem suporte@inilog.com.br
rem www.inilog.com
rem @francisneydelmondes @inilog #inilog #francisneydelmondes

netsh interface ip set address name="Ethernet" dhcp
netsh interface ip set dnsservers name="Ethernet" dhcp
mshta vbscript:Execute("msgbox ""Comando executado!. Configurado para conectar via [DHCP]    https://inilog.com/hesk "":close")
echo Comando executado!. Configurado para conectar via [DHCP] 
  exit
goto menu
:opcao0
exit
goto menu
exit

