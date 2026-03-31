
# Swagger-UI for Otobo

## open swagger-ui for a running Otobo instance

The Swagger UI is at https://localhost/otobo-web/js/thirdparty/swagger/index.html
but there is now also a friendly link in the Admin UI for "openApi" that
just redirects there.

## where is the metadata

Find the static metadata at var/webservices/metadata. 

## where are the ready2adopt webservice import files

The ready2adopt webservice import files are right next to the metadat in
var/webservices/examples.

## how to update swagger ui

1) clone swagger-ui from GitHub:

https://github.com/swagger-api/swagger-ui

2) copy the 'dist' folder to $OTOBO_HOME/var/httpd/htdocs/js/thirdparty/swagger

3) update the url in file 'swagger-initialzer.js' to point to the Otobo OpenAPI document

```JavaScript
	url : '/otobo/index.pl?Action=Swagger',
```
