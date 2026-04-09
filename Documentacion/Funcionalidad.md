# Funcionamiento
- [Funcionamiento](#funcionamiento)
  - [Autenticación](#autenticación)
  - [Proceso de mensaje](#proceso-de-mensaje)
    - [**Envío** **de** **saludo**](#envío-de-saludo)
      - [**Envío** **desde** **app**](#envío-desde-app)
      - [**Envío** **desde** **pulsera**](#envío-desde-pulsera)
    - [**Modificar** **el** **archivo**](#modificar-el-archivo)
    - [**Recibir** **el** **mensaje**](#recibir-el-mensaje)
    - [**Analizar** **los** **datos**](#analizar-los-datos)
    - [**Comprobar** **las** **configuraciones**](#comprobar-las-configuraciones)
    - [**Saludo**](#saludo)

El funcionamiento central de las pulseras no es nada del otro mundo, ya que no haremos uso de grandes APIs a nivel servidor, gracias a Firebase tendremos el trabajo muy facilitado, pues nos gestionará la BBDD y la autenticación de usuarios.

## Autenticación
La autenticación de nuestros usuarios será a través de FirebaseAuth, el cuál es un módulo aparte del de la base de datos, así que no tendremos que preocuparnos tanto por la seguridad, pues nos verificaremos contra ello y solo nos devolverá el token de usuario, así no pasarán las contraseñas por la base de datos principal.

## Proceso de mensaje
El proceso de mensaje es sencillo de entender, pues este depende de un cambio en la base de datos, es decir, al enviar un saludo (entendiendo como saludo el envío del mensaje) la app cambiará los campos incluídos en el **map** de **Message** dentro de los archivos de la colección **links**, y la app receptora verá ese cambio, y analizando los datos que vea, enviará un mensaje a **su pulsera**. Yendo paso a paso:
![img](./imgs/Hermodr%20lógica.jpg)

### **Envío** **de** **saludo**
Para poder enviar un saludo llegamos a dos conclusiones, y es que si simplemente dejasemos conectarse via pulseras, no podrías usar nuestra app con más de una persona si solo tienes una pulsera, como podría ser una madre con 3 hijos, o un grupo de amigos, entonces llegamos a la conclusión de que deberías poder enviar mensajes directamente desde la app, así pues, recibirás todas las notificaciones en tu pulsera, independientemente de quién lo mande, pero desde la pulsera solo enviarás a un enlace. Para poder gestionar esto es que existe el campo BandN.DestinyLinkID en todos los usuarios con pulsera, para ver a qué enlace hace referencia.
#### **Envío** **desde** **app**
El envío desde app es el más sencillo, desde cada enlace con un amigo podrás darle a un botón de envío, que tendrá como destino el archivo de **link** pertinente,
#### **Envío** **desde** **pulsera**
Cuando registres a un nuevo **amigo** tendrás la opción de definirlo como el favorito para tu pulsera (obviamente se puede editar en cualquier momento), esto hará que al pulsar el botón de esta pulsera se consulte en el archivo de usuario, en el que se buscará a qué **map** corresponde la **MAC**, y entonces mirará el campo **BandX.DestinyLinkID**, lo que contendrá el nombre del archivo que corresponda al enlace en cuestión.
### **Modificar** **el** **archivo**
Ahora que ya está ubicado el archivo que corresponde a la persona a la que le queremos mandar el **saludo**, editaremos el archivo, concretamente los campos del **map** **Message**, pues necesitaremos cambiar el campo **Message.Sent** a true para iniciar el proceso. Así que antes de eso el emisor pondrá su **UID** en el campo **Message.Last_Sent** para que la **app** sepa quién ha modificado el campo **Message.Sent**, además, utilizaremos el campo **Message.Last_Second** para evitar problemas de **spam**.
### **Recibir** **el** **mensaje**
Para recibir el mensaje usaremos la función de **stream** que tiene dart, pues nos permitirá que dart **"esté atento"** al campo **Message.Sent** en todos los archivos en los que su **UID** se ve contemplado en el campo **Users**, esto hará que firebase le avise cuando se cambie, y ahí **empezará** el proceso.
### **Analizar** **los** **datos**
En este paso, lo que hará la app al ver que el campo **Message.Sent** está en **True** será comprobar **Message.Last_Sent** y comprobar si el **UID** que sale es el suyo, en caso de serlo, ignorará el cambio, pero si no lo es, entonces seguirá con el proceso de **saludo**.
### **Comprobar** **las** **configuraciones**
Por último, antes de enviar el mensaje, comproborá la **ConfgN** correspondiente de su **UID** para saber a qué pulsera mandárselo (con el campo **ConfgN.Band**) o con qué color recibirá el mensaje (con el campo **ConfgN.Color**).
### **Saludo**
Ahora sí, se enviará el **saludo** a la pulsera final con la información pertinente, y esta ejecutará el **resultado final**.