# Dockerfile para Cadete - PHP + Apache en puerto 8080
# Soporte para proxy corporativo y extensiones MySQL
FROM php:8.2-apache

# Args para proxy corporativo
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

# Variables de entorno para proxy
ENV HTTP_PROXY=$HTTP_PROXY \
    HTTPS_PROXY=$HTTPS_PROXY \
    NO_PROXY=$NO_PROXY

# Instalar extensiones PHP necesarias para MySQL y funcionalidades web
RUN set -eux; \
    apt-get update; \
    apt-get install -y \
        libzip-dev \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
        unzip \
        git; \
    # Extensiones PHP
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install \
        mysqli \
        pdo \
        pdo_mysql \
        gd \
        zip; \
    # Habilitar módulos Apache necesarios
    a2enmod rewrite headers; \
    # Cambiar Apache del puerto 80 al 8080 para alinear con Service OpenShift
    sed -ri 's/Listen 80/Listen 8080/g' /etc/apache2/ports.conf; \
    sed -ri 's/:80/:8080/g' /etc/apache2/sites-available/000-default.conf; \
    # Limpiar cache apt
    rm -rf /var/lib/apt/lists/*

# Directorio de trabajo
WORKDIR /var/www/html

# Copiar código fuente de Cadete
COPY . /var/www/html/

# Ajustar permisos para www-data
RUN chown -R www-data:www-data /var/www/html && \
    chmod -R 755 /var/www/html

# Exponer puerto 8080 (alineado con Service cadete3)
EXPOSE 8080

# Comando por defecto
CMD ["apache2-foreground"]