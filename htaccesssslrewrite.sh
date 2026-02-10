#! /bin/sh
echo Hello, name?
read name
echo Please Enter the Google Authentication code associated with $name.
read -s code
if [[ $code == 1 ]]
then
 echo Home...
 read home
 echo Location...
 read loc
 echo domain without tld
 read domain
 echo tld
 read tld
 echo $'DirectoryIndex index.php index.html\n<IfModule mod_rewrite.c> \nRewriteEngine On\nRewriteCond %{HTTPS} off\nRewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R,L]\n</IfModule>\nHeader always set Content-Security-Policy: upgrade-insecure-requests \nRewriteEngine On\nRewriteCond %{HTTP_HOST} '$domain$'\.'$tld$' [NC]\nRewriteCond %{SERVER_PORT} 80\nRewriteRule ^(.*)$ https://'$domain$'.'$tld$'/$1 [R,L]' >| $home/$loc/.htaccess
else
 echo Enter the correct code. Come back later.Byeeee....$name
fi