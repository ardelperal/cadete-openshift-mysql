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
    Use ModelRecursos\Personal;

    //Usado para la lectura del token LDAP
    use Firebase\JWT\JWT;
    use Firebase\JWT\Key;

    //El Router se va a encargar de tener todas las rutas y controladores, y hacer llamar a ciertos métodos
    class Router{

        //Variable que guarda las rutas que usarán el método GET
        public $rutasGET = [];

        //Variable que guarda las rutas que usarán el método POST
        public $rutasPOST = [];

        /* Con PROT protegemos rutas para asegurarnos que solo se pueden acceder a ellas 
        /si estás autorizado */
        public $rutasPROT = [];

        // Helper para loguear en la consola del navegador el flujo de autenticación
        private function consoleLog($message, $data = null) {
            $jsonMsg = json_encode($message, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
            $jsonData = $data !== null ? json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PARTIAL_OUTPUT_ON_ERROR) : 'null';
            echo "<script>\n            try {\n              window.CADETE_AUTH_LOG = window.CADETE_AUTH_LOG || [];\n              window.CADETE_AUTH_LOG.push({ts: Date.now(), msg: $jsonMsg, ctx: $jsonData});\n              console.log('%c[CADETE AUTH]','color:#0a84ff;font-weight:bold', $jsonMsg, $jsonData);\n            } catch(e) {}\n            </script>";
        }

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
                try {
                try {
                include_once VIEWS_URL . "/layout.php";
            } catch (\Throwable $e) {
                $this->consoleLog('Error renderizando layout; se mostrará contenido sin layout', ['error' => $e->getMessage(), 'type' => get_class($e)]);
                echo $contenido;
            }
            } catch (\Throwable $e) {
                $this->consoleLog('Error renderizando layout; se mostrará contenido sin layout', ['error' => $e->getMessage(), 'type' => get_class($e)]);
                echo $contenido;
            }
            }
            
        }

        public function comprobarLogin($urlActual){

            // Inicio del flujo de autenticación con Siteminder
            $this->consoleLog('Inicio flujo de autenticación Siteminder', ['request_uri' => $_SERVER['REQUEST_URI'] ?? null]);

            //Intentamos leer la cabecera Authorization para extraer el token JWT
            $headers = function_exists('getallheaders') ? getallheaders() : [];
            // Eliminado volcado de cabeceras a HTML para evitar mostrar JWT
            $this->consoleLog('Cabeceras recibidas', $headers);

            // Normalizar claves y buscar Authorization en varias fuentes (cabeceras y $_SERVER)
            $headersLower = is_array($headers) ? array_change_key_case($headers, CASE_LOWER) : [];
            $serverAuth = $_SERVER['HTTP_AUTHORIZATION'] ?? ($_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? null);
            $authHeader = $headersLower['authorization'] ?? $serverAuth ?? '';
            $this->consoleLog('Fuentes de Authorization', [
                'headers.authorization' => $headersLower['authorization'] ?? null,
                'HTTP_AUTHORIZATION' => $_SERVER['HTTP_AUTHORIZATION'] ?? null,
                'REDIRECT_HTTP_AUTHORIZATION' => $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? null,
                'selected' => $authHeader
            ]);

            //LOGIN CON EL TOKEN JWT
            if (preg_match('/Bearer\s(\S+)/', $authHeader, $matches)) {

                $this->consoleLog('Authorization con Bearer detectado');

                $jwt = trim($matches[1]);
                // No imprimimos el token en el HTML para evitar exponerlo públicamente
                $this->consoleLog('JWT extraído de Authorization', ['token' => $jwt]);

                //Verifica que el token está bien compuesto
                if (substr_count($jwt, '.') !== 2) {
                    $this->consoleLog('JWT mal formado, no tiene 3 segmentos', ['segmentos' => substr_count($jwt, '.')]);
                    throw new Exception("Token mal formado, no tiene 3 segmentos");
                } else {
                    $this->consoleLog('JWT con formato correcto');
                }

                try {

                    $secret = $_ENV['LDAP_SECRET'] ?? null;
                    $this->consoleLog('Decodificando JWT', ['alg' => 'HS256', 'secret_present' => $secret ? true : false]);
                    $decoded = JWT::decode($jwt, new Key($secret, 'HS256'));

                    //Extraemos el email del payload
                    $email = $decoded->mail ?? null;
                    $this->consoleLog('JWT decodificado', ['email' => $email]);

                    if ($email) {
                        $this->consoleLog('Email extraído del JWT', ['email' => $email]);

                        $usuario = Personal::findByEmail($email);
                        $this->consoleLog('Búsqueda de usuario en Personal', [
                            'encontrado' => $usuario ? true : false,
                            'user' => $usuario->user ?? null,
                            'id' => $usuario->id ?? null
                        ]);

                        $_SESSION['id_user'] = $usuario->user;
                        $_SESSION['nombre'] = $usuario->nombre . " " . $usuario->primer_apellido . " " . $usuario->segundo_apellido;
                        $_SESSION['avatar'] = "/build/img/users/" . $usuario->id . ".jpg";
                        $_SESSION['rol'] = Personal::cargarRol($usuario->email);
                        $_SESSION['permisos'] = explode(',', Login::cargarPermisos($_SESSION['rol']));
                        $_SESSION['login'] = true;

                        $this->consoleLog('Sesión de usuario inicializada', [
                            'id_user' => $_SESSION['id_user'],
                            'rol' => $_SESSION['rol'],
                            'permisos_count' => is_array($_SESSION['permisos']) ? count($_SESSION['permisos']) : null
                        ]);

                    } else {
                        $this->consoleLog('Email no encontrado en JWT, redirigiendo a login CADETE');
                        //Email no encontrado en token
                        $this->redirigirAlLoginCADETE($urlActual);
                    }

                } catch (Exception $e) {
                    // Token inválido o expirado
                    $this->consoleLog('Error al decodificar JWT', ['error' => $e->getMessage()]);
                    $this->redirigirAlLoginCADETE($urlActual);
                }
            }

            //LOGIN CON CADETE
            else {

               $this->consoleLog('Authorization sin Bearer o no presente, redirigiendo a login CADETE', ['Authorization' => $authHeader]);
               $this->redirigirAlLoginCADETE($urlActual);
                                
            }

        }

        public function redirigirAlLoginCADETE($urlActual) {

            $this->consoleLog('Entrando a redirigirAlLoginCADETE', [
                'urlActual' => $urlActual,
                'request_uri' => $_SERVER["REQUEST_URI"] ?? null,
                'rutaProtegida' => in_array($urlActual, $this->rutasPROT)
            ]);

            if(!isset($_SESSION['login']) && $_SERVER["REQUEST_URI"] <> '/login'){

                $this->consoleLog('No hay sesión activa; mostrando login CADETE');
                include_once VIEWS_URL . "/00/Login/login.php";
                echo "<script> showSnackbar('No se ha encontrado el token JWT. Se realizará el login con CADETE.','ico__alerta w','red'); </script>";
                exit;
            }
            elseif(in_array($urlActual, $this->rutasPROT) && !$_SESSION['login']) {
                $this->consoleLog('Acceso a ruta protegida sin login; mostrando 404', ['ruta' => $urlActual]);
                ob_start();
                include_once VIEWS_URL . "/404.php";
                $contenido = ob_get_clean();
                try {
                    include_once VIEWS_URL . "/layout.php";
                } catch (\Throwable $e) {
                    $this->consoleLog('Error renderizando layout; se mostrará contenido sin layout', ['error' => $e->getMessage(), 'type' => get_class($e)]);
                    echo $contenido;
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
            try {
                include_once VIEWS_URL . "/layout.php";
            } catch (\Throwable $e) {
                $this->consoleLog('Error renderizando layout; se mostrará contenido sin layout', ['error' => $e->getMessage(), 'type' => get_class($e)]);
                echo $contenido;
            }
            
        }

        public function paginaError(){

            Router::render('/404', []);

        }

    }

?>

