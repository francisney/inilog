<?php
/* O acesso antigo não apaga mais todas as notas por GET. */
header('Location: index.php?scope=trash',true,303);
exit;
