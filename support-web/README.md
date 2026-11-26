# INILOG — painéis de suporte

Código dos painéis hospedados na HostGator. Esta versão mantém o banco MySQL existente dos computadores e usa JSON privado para notas; não exige novo banco.

## Painéis

- `source/628/`: catálogo, upload, download, visualização de texto, edição com cópia anterior e lixeira.
- `source/geral/`: lojas, computadores, IP, observações e identificadores de acesso; busca, filtro por loja, edição, exclusão e CSV.
- `source/notas/`: notas atuais e antigas, busca, favoritos, edição e lixeira com restauração.
- `source/_inilog/`: autenticação PHP, proteção dos formulários, estilos e JavaScript compartilhados.

Os downloads diretos dentro de `628/files/` continuam públicos. Os arquivos `old.txt` e `mensagens.txt` também permanecem acessíveis diretamente, conforme a escolha do proprietário. Alterações nas notas regeneram essas cópias em texto. A autenticação protege os painéis e suas operações de gerenciamento.

## Dados e configuração

A configuração PHP, os dados JSON e as cópias anteriores ficam em `.inilog-support`, fora de `public_html`. Não colocar esse diretório no Git. A senha do gerenciador de arquivos é preservada. O painel de notas usa a senha escolhida pelo proprietário, armazenada em forma de hash. A proteção por `.htaccess` gerenciada pelo cPanel em `geral/` permanece intacta.

A tabela existente `toy` mantém todos os campos e IDs. Os nomes de campos legados são mapeados para rótulos em português, sem alteração do esquema. A conexão é obtida da configuração privada; consultas que usam dados de formulários são preparadas.

## Implantação

O conteúdo de `source/` corresponde ao diretório `public_html/suporte/`. Publicar somente os arquivos dessa pasta. **Não copiar arquivos de fixtures ou staging para `628/files/`.** As distribuições do Git são sincronizadas separadamente a partir da branch `main`.

`tools/setup.php` é uma ferramenta CLI que preserva a configuração anterior e importa as notas. `tools/deploy.py` valida o código PHP, cria uma cópia anterior e publica os arquivos por substituição, preservando o `.htaccess` do cPanel. Ambos precisam de caminhos e configuração válidos da hospedagem. Os scripts de implantação e teste não devem ficar em diretório público.

Para manutenção, preservar o diretório privado e restaurar o arquivo anterior a partir do backup, sem restaurar uma cópia antiga do banco sobre registros posteriores. Os backups contêm dados privados e não devem ser enviados ao repositório.

## Validação realizada

- 34 verificações de integração em staging, com servidor PHP restrito ao loopback.
- Cadastro, edição, busca, exclusão e CSV dos computadores; os 281 registros originais permaneceram intactos.
- Importação de 67 notas, incluindo 46 notas antigas de `old.txt`.
- Edição concorrente, CSRF, conteúdo escapado, confinamento de caminhos e recuperação de arquivos/notas.
- Revisão visual dos três painéis no navegador usando dados de demonstração.
- Verificação pública de `update.ps1`, download completo de `Inilog_Cloud.exe` e acesso direto a `old.txt` sem login.

O teste por Python HTTP a partir da VPS recebeu erro 406 do ModSecurity. A verificação por navegador funcionou; não foi necessário alterar as regras do firewall da hospedagem.
