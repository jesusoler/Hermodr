#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>

// ======================
// Pines
// ======================

const int PIN_PULSADOR = 14;
const int PIN_VIBRADOR = 4;

// ======================
// UUIDs BLE
// ======================

// Servicio principal
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"

// ESP32 -> App
#define CHARACTERISTIC_TX   "abcd1111-1234-1234-1234-123456789abc"

// App -> ESP32
#define CHARACTERISTIC_RX   "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLECharacteristic *txCharacteristic;

bool dispositivoConectado = false;

// Callback  de la conexión BLE, la principal
class MyServerCallbacks: public BLEServerCallbacks {

  void onConnect(BLEServer* pServer) {
    dispositivoConectado = true;
    Serial.println("Movil conectado");
  }

  void onDisconnect(BLEServer* pServer) {
    dispositivoConectado = false;
    Serial.println("Movil desconectado");

    BLEDevice::startAdvertising();
  }
};


// Callback de cuando se recibe la señal BLE
class MyCallbacks: public BLECharacteristicCallbacks {

  void onWrite(BLECharacteristic *pCharacteristic) {

    String valor = pCharacteristic->getValue().c_str();

    if (valor.length() > 0) {

      Serial.print("Mensaje recibido: ");
      Serial.println(valor);

      if (valor == "vibrate") {

        digitalWrite(PIN_VIBRADOR, HIGH);

        delay(2000);

        digitalWrite(PIN_VIBRADOR, LOW);
      }
    }
  }
};

void setup() {

  Serial.begin(115200);

  pinMode(PIN_PULSADOR, INPUT_PULLDOWN);
  pinMode(PIN_VIBRADOR, OUTPUT);


  // BLE

  BLEDevice::init("PulseraESP32");

  BLEServer *pServer = BLEDevice::createServer();

  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Característica TX
  txCharacteristic = pService->createCharacteristic(
                       CHARACTERISTIC_TX,
                       BLECharacteristic::PROPERTY_NOTIFY
                     );

  // Para qeu funcione el canal RX
  BLECharacteristic *rxCharacteristic = pService->createCharacteristic(
                                          CHARACTERISTIC_RX,
                                          BLECharacteristic::PROPERTY_WRITE
                                        );

  rxCharacteristic->setCallbacks(new MyCallbacks());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();

  pAdvertising->start();

  Serial.println("BLE iniciado");
}

void loop() {

  int estadoBoton = digitalRead(PIN_PULSADOR);

  if (estadoBoton == HIGH && dispositivoConectado) {

    Serial.println("Boton pulsado");

    txCharacteristic->setValue("pressed");

    txCharacteristic->notify();

    delay(500);
  }

  delay(50);
}