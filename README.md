Este es el proyecto intermodular de Jesús Soler y Diego Domínguez.
Se basa en unas pulseras de saludo, estas mandarán una vibración a otra pulsera al pulsar un botón, esto se hará a través de una app y conexión ble.
El diagrama de funcionamiento sería tal que:
Botón pulsera 1 --> Mensaje BLE a app1 --> App1 manda mensaje a API --> API busca la pareja de la app1 --> Manda mensaje a app2 -->
--> App2 envía mensaje a pulsera 2 --> Pulsera 2 emite una vibración

La app móvil está creada con flutter, la API está en Firebase y las pulseras con arduino y BLE
