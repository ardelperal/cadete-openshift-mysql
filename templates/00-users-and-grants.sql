-- Template de creación y concesión de permisos para MySQL
-- IMPORTANTE: Reemplazar 'user' y la contraseña por los valores reales del entorno
-- No committear credenciales reales en el repositorio

CREATE USER IF NOT EXISTS 'user'@'%' IDENTIFIED BY 'onDpoPsmeNepIT123';
-- La sintaxis correcta para conceder permisos globales es sobre *.*
GRANT SELECT, INSERT, UPDATE, DELETE, FILE ON *.* TO 'user'@'%';
FLUSH PRIVILEGES;
