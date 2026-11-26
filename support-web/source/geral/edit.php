<?php
header('Location: index.php?edit='.(int)($_GET['id']??0),true,303);
exit;
