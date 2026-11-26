<?php
declare(strict_types=1);
require dirname(__DIR__).'/_inilog/app.php';
require_auth('computers',true);
require __DIR__.'/dbcontroller.php';
$fields=['name'=>'Loja / unidade','code'=>'Nome do computador','category'=>'IP / endereço','price'=>'Observações / setor','stock_count'=>'AnyDesk / outro ID'];
$error='';$rows=[];$total=0;$count=0;$stores=[];$edit=null;
$q=is_string($_GET['q']??null)?trim($_GET['q']):'';
$store=is_string($_GET['store']??null)?trim($_GET['store']):'';
$page=max(1,(int)($_GET['page']??1));$perPage=40;
function computer_values(array $input): array {
    $out=[];
    foreach(['name'=>255,'code'=>255,'category'=>255,'price'=>200,'stock_count'=>200] as $field=>$limit) {
        $v=is_string($input[$field]??null)?trim($input[$field]):'';
        if (!preg_match('//u',$v)||text_length($v)>$limit) throw new RuntimeException('Um dos campos excede o tamanho permitido. Revise os dados.');
        $out[$field]=$v;
    }
    if ($out['name']===''||$out['code']==='') throw new RuntimeException('Informe a loja e o nome do computador.');
    return $out;
}
function computer_query(mysqli $db,string $sql,string $types='',array $params=[]): mysqli_stmt {
    $stmt=$db->prepare($sql);if($types!=='')$stmt->bind_param($types,...$params);$stmt->execute();return $stmt;
}
try {
    $db=(new DBController())->connectDB();
    if ($_SERVER['REQUEST_METHOD']==='POST') {
        check_csrf();$action=$_POST['action']??'';
        $id=filter_var($_POST['id']??null,FILTER_VALIDATE_INT);
        if ($action==='save') {
            $values=computer_values($_POST);
            if ($id) {
                $db->begin_transaction();
                $old=computer_query($db,'SELECT * FROM toy WHERE id=? FOR UPDATE','i',[$id])->get_result()->fetch_assoc();
                if (!$old || !hash_equals(fingerprint($old),(string)($_POST['revision']??''))) throw new RuntimeException('Este computador mudou em outra janela. Recarregue para revisar antes de salvar.');
                computer_query($db,'UPDATE toy SET name=?,code=?,category=?,price=?,stock_count=? WHERE id=?','sssssi',[...array_values($values),$id]);$db->commit();
                flash('Computador atualizado.');
            } else {
                computer_query($db,'INSERT INTO toy (name,code,category,price,stock_count) VALUES (?,?,?,?,?)','sssss',array_values($values));flash('Computador cadastrado.');
            }
        } elseif ($action==='delete') {
            if (!$id) throw new RuntimeException('Computador não encontrado.');
            $db->begin_transaction();
            $old=computer_query($db,'SELECT * FROM toy WHERE id=? FOR UPDATE','i',[$id])->get_result()->fetch_assoc();
            if (!$old||!hash_equals(fingerprint($old),(string)($_POST['revision']??''))) throw new RuntimeException('Este computador mudou. Recarregue antes de excluir.');
            $trash=private_dir().'/computer-trash';if(!is_dir($trash))mkdir($trash,0700,true);
            write_json($trash.'/'.uid().'.json',['deleted_at'=>gmdate('c'),'row'=>$old]);
            computer_query($db,'DELETE FROM toy WHERE id=?','i',[$id]);$db->commit();flash('Computador excluído. Uma cópia foi guardada no backup privado.');
        } else throw new RuntimeException('Ação não reconhecida.');
        redirect('index.php');
    }
    $count=(int)$db->query('SELECT COUNT(*) AS n FROM toy')->fetch_assoc()['n'];
    $stores=$db->query('SELECT DISTINCT name FROM toy ORDER BY name')->fetch_all(MYSQLI_ASSOC);
    $where=[];$types='';$params=[];
    if($q!==''){$where[]='(name LIKE ? OR code LIKE ? OR category LIKE ? OR price LIKE ? OR stock_count LIKE ?)';$types.='sssss';$params=array_fill(0,5,'%'.$q.'%');}
    if($store!==''){$where[]='name=?';$types.='s';$params[]=$store;}
    $filter=$where?' WHERE '.implode(' AND ',$where):'';
    $total=(int)computer_query($db,'SELECT COUNT(*) AS n FROM toy'.$filter,$types,$params)->get_result()->fetch_assoc()['n'];
    $pages=max(1,(int)ceil($total/$perPage));$page=min($page,$pages);$offset=($page-1)*$perPage;
    $rows=computer_query($db,'SELECT * FROM toy'.$filter.' ORDER BY name,code,id LIMIT ? OFFSET ?',$types.'ii',[...$params,$perPage,$offset])->get_result()->fetch_all(MYSQLI_ASSOC);
    if(isset($_GET['edit']))$edit=computer_query($db,'SELECT * FROM toy WHERE id=?','i',[(int)$_GET['edit']])->get_result()->fetch_assoc();
    if(isset($_GET['export'])) {
        header('Content-Type: text/csv; charset=UTF-8');header('Content-Disposition: attachment; filename="computadores-inilog-'.date('Y-m-d').'.csv"');
        $out=fopen('php://output','w');fwrite($out,"\xEF\xBB\xBF");fputcsv($out,['Registro',...array_values($fields)],';','"','');
        $export=computer_query($db,'SELECT * FROM toy'.$filter.' ORDER BY name,code,id',$types,$params)->get_result();
        while($row=$export->fetch_assoc()){foreach($row as &$value)if(is_string($value)&&preg_match('/^[=+@\-\t\r]/',$value))$value="'".$value;unset($value);fputcsv($out,[$row['id'],...array_map(fn($key)=>$row[$key],array_keys($fields))],';','"','');}exit;
    }
} catch(Throwable $e) {if(isset($db))try{$db->rollback();}catch(Throwable){} $error=fail_message($e);}
$new=isset($_GET['new']);
if($error&&($_POST['action']??'')==='save'){$edit=$_POST;$new=empty($_POST['id']);}
require __DIR__.'/view.php';
