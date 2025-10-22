<?php

    /*
    ================================================================
    Router es un modelo que controlará la navegación por la web.
    El Router se va a encargar de tener todas las rutas y controladores, y hacer 
    llamar a ciertos métodos
    ================================================================
    */

    namespace MVC;

    use ModelIndicadores\IndAccesoPaginasWeb;
    use ModelGeneral\Mantenimiento;
    use ModelGeneral\Login;

    //El Router se va a encargar de tener todas las rutas y controladores, y hacer llamar a ciertos métodos
    class Router{

        //Variable que guarda las rutas que usarán el método GET
        public $rutasGET = [];

        //Variable que guarda las rutas que usarán el método POST
        public $rutasPOST = [];

        /* Con PROT protegemos rutas para asegurarnos que solo se pueden acceder a ellas 
        /si estás autorizado */
        public $rutasPROT = [];

        public function get($url, $fn) {

            /*
            ===============================================================
            Controla la navegación usando métodos GET.
            Recibe como parámetros la url actual que estemos visitando, y la función 
            asociada a esa URL.
            ================================================================
            */

            $this->rutasGET[$url] = $fn;

        }

        public function post($url, $fn) {

            /*
            ================================================================
            Controla la navegación usando métodos POST.
            Recibe como parámetros la url actual que estemos visitando, y la función 
            asociada a esa URL.
            ================================================================
            */

            $this->rutasPOST[$url] = $fn;

        }

        public function prot($url) {

            /*
            ================================================================
            Controla la navegación usando métodos POST.
            Recibe como parámetros la url actual que estemos visitando, y la función 
            asociada a esa URL.
            ================================================================
            */

            $this->rutasPROT[] = $url;

        }

        public function comprobarRutas() {    

            /*
            ================================================================
            Revisa que las rutas estén definidas en el router, así como validar el tipo de request (GET o POST)
            ================================================================
            */

            //Obtenemos la url
            $urlActual = $_SERVER['PATH_INFO'] ?? '/';

            //Comprobamos que las rutas están $_SERVER['REQUEST_METHOD']
            if($_SERVER['REQUEST_METHOD'] === 'GET') {
                $fn = $this->rutasGET[$urlActual] ?? null;
            }
            else {
                $fn = $this->rutasPOST[$urlActual] ?? null;
            }

            //Comprobamos que el usuario está logueado para redireccionarle o no a la página de login
            self::comprobarLogin($urlActual);

            //Si la web está en mantenimiento, redirige a la página oportuna
            self::comprobarMantenimiento();

            //Si la web no está en mantenimiento, actúa con normalidad
            if($fn) {  
               
                //La url existe y hay una función asociada
                call_user_func($fn, $this);
            }
            else
            {
                //Almacenamos los siguientes datos en memoria
                ob_start();                                             
                include_once VIEWS_URL . "/404.php";

                //Limpia el buffer
                $contenido = ob_get_clean();                           
                include_once VIEWS_URL . "/layout.php";
            }
            
        }

        public function comprobarLogin($urlActual){

            //Comprobamos si ha recibido la cabecera
            if (isset($_SERVER['HTTP_SMUSER'])) 
            {                

                $usuario = Personal::findByEmail($_SERVER['HTTP_SMUSER']['mail']);

                $_SESSION['id_user'] = $usuario->user;
                $_SESSION['nombre'] = $usuario->nombre . " " . $usuario->primer_apellido . " " . $usuario->segundo_apellido;
                $_SESSION['avatar'] = "/build/img/users/" . $usuario->id . ".jpg";                
                $_SESSION['rol'] = Personal::cargarRol($usuario->email);
                $_SESSION['permisos'] = explode(',', Login::cargarPermisos($_SESSION['rol']));
                $_SESSION['login'] == true;
                
                $login->id = $usuario->user;
             
            }
            else
            {

                //Si no tiene cabecera, le pedimos el login interno
                if(!isset($_SESSION['login']) & $_SERVER["REQUEST_URI"] <> '/login'){
                    include_once VIEWS_URL . "/00/Login/login.php";
                    exit;
                }       
                
                //Si es una ruta protegida, verificamos si el usuario está autorizado
                if(in_Array($urlActual, $this->rutasPROT) && !$_SESSION['login']) {
                
                    //En el caso de que sea una ruta protegida y no estemos logados, nos envía a la página de login
                    
                    //Almacenamos los siguientes datos en memoria
                    ob_start();     
                    include_once VIEWS_URL . "/404.php";

                    //Limpia el buffer
                    $contenido = ob_get_clean();    
                    
                    include_once VIEWS_URL . "/layout.php";
                    
                }

            }

        }

        public function comprobarMantenimiento(){
  
            $mantenimiento = Mantenimiento::checkMantenimiento();
            
            if($mantenimiento->mantenimiento == 1){

                if($_POST){

                    $adm = Login::comprobarAdminMto($_POST['email']);
    
                    if(!$adm){
                        //Almacenamos los siguientes datos en memoria                                           
                        include_once VIEWS_URL . "/mantenimiento.php";
                        exit;
                    }    

                }

            }            

        }

        public function render($view, $datos=[]) {

            /*
            ================================================================
            Renderiza las vistas para cargarlas en el "esqueleto" layout.php
            ================================================================
            */

            //Obtenemos los datos del array
            foreach($datos as $key => $value) {

                //El doble signo de $$ signfinica 'variable de variable'
                $$key = $value;
            }

            //Registramos el indicador
            if (isset($_SESSION['id_user'])) {
                IndAccesoPaginasWeb::crearRegistro($_SESSION['id_user'], $_SERVER['REQUEST_URI']);
            }

            //Almacenamos los siguientes datos en memoria
            ob_start();     
            include_once VIEWS_URL . "/$view.php";

            //Limpia el buffer
            $contenido = ob_get_clean();    
            include_once VIEWS_URL . "/layout.php";
            
        }

        public function paginaError(){

            Router::render('/404', []);

        }

    }

?>