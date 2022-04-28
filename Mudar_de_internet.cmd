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
:programa
cls
:menu
cls
color 
echo                 INILOG - Support
echo  _______________________________________
echo * 1. Conectar na rede da [Vivo]         
echo * 2. Conectar na rede da [OI]            
echo * 3. Conectar via [DHCP]  
echo -           
echo * 0. SAIR [EXIT]                                  
echo  _______________________________________
set /p opcao=    Escolha e tecle [ENTER]: 
echo ------------------------------
if %opcao% equ 1 goto opcao1
if %opcao% equ 2 goto opcao2
if %opcao% equ 3 goto opcao3
if %opcao% equ 0 goto opcao0
:opcao1
rem script conectar na rede [Vivo]
netsh interface ip set address name="rede" static 192.168.15.119 255.255.255.0 192.168.15.1
netsh interface ip set dnsservers name="rede" static 192.168.15.1 primary no
mshta vbscript:Execute("msgbox ""Comando executado!. Conectado na rede da [Vivo]    https://inilog.com/hesk "":close")
exit
goto menu
:opcao2
rem Script conectar na rede [OI]
netsh interface ip set address name="rede" static 192.168.1.119 255.255.255.0 192.168.1.1
netsh interface ip set dnsservers name="rede" static 192.168.1.1 primary no
mshta vbscript:Execute("msgbox ""Comando executado!. Conectado na rede da [OI]    https://inilog.com/hesk "":close")
exit
goto menu
:opcao3
rem Script Conexão Automática [DHCP]
netsh interface ip set address name="rede" dhcp
netsh interface ip set dnsservers name="rede" dhcp
mshta vbscript:Execute("msgbox ""Comando executado!. Configurado para conectar via [DHCP]    https://inilog.com/hesk "":close")
exit
goto menu
:opcao0
exit
goto menu
exit

