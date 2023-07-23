@echo off
for /f "tokens=*" %%a in ('fsutil behavior query DisableDeleteNotify ^| find "0"') do set trimStatus=%%a
if defined trimStatus (
    echo O TRIM já está habilitado no seu sistema.
) else (
    fsutil behavior set DisableDeleteNotify 0
    for /f "tokens=*" %%a in ('fsutil behavior query DisableDeleteNotify ^| find "0"') do set newTrimStatus=%%a
    if defined newTrimStatus (
        echo O TRIM foi habilitado com sucesso no seu sistema.
    ) else (
        echo Não foi possível habilitar o TRIM no seu sistema. Verifique se você tem as permissões necessárias e se o seu disco suporta TRIM.
    )
)


pause
