<<<<<<< HEAD
# hermodr

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
=======
Este es el proyecto intermodular de Jesús Soler y Diego Domínguez.
Se basa en unas pulseras de saludo, estas mandarán una vibración a otra pulsera al pulsar un botón, esto se hará a través de una app y conexión ble.
El diagrama de funcionamiento sería tal que:

Botón pulsera 1 --> Mensaje BLE a app1 --> App1 manda mensaje a API --> API busca la pareja de la app1 --> Manda mensaje a app2 -->
App2 envía mensaje a pulsera 2 --> Pulsera 2 emite una vibración

La app móvil está creada con flutter, la API está en Firebase y las pulseras con arduino y BLE
>>>>>>> f3ab920410ffe749ae56a8227a921ddb1682f942
