<?php
/* Compatibilidade com o controlador antigo, sem credenciais no diretório público. */
class DBController {
    private ?mysqli $conn=null;
    public function connectDB(): mysqli {
        if ($this->conn===null) {
            if (!function_exists('config')) require_once dirname(__DIR__).'/_inilog/app.php';
            $cfg=config()['database'];mysqli_report(MYSQLI_REPORT_ERROR|MYSQLI_REPORT_STRICT);
            $this->conn=new mysqli($cfg['host'],$cfg['user'],$cfg['password'],$cfg['database']);
            $this->conn->set_charset('utf8mb4');
        }
        return $this->conn;
    }
    public function runQuery($query): array {return $this->connectDB()->query($query)->fetch_all(MYSQLI_ASSOC);}
    public function numRows($query): int {return $this->connectDB()->query($query)->num_rows;}
    public function executeQuery($query): bool {return (bool)$this->connectDB()->query($query);}
}
