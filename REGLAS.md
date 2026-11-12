# Directrices de Desarrollo, Arquitectura y UI para el Agente (AppStreaming)

Este documento establece las reglas estrictas de arquitectura, orden modular, diseño visual y compatibilidad multiplataforma que el agente de desarrollo debe seguir obligatoriamente durante la construcción de la aplicación **AppStreaming** (orientada a APK para Android, IPK para LG webOS y futuras plataformas como Samsung Tizen).

---

## 1. Principios Fundamentales

* **Clean Architecture Estricta:** Separación absoluta de responsabilidades en capas (`core`, `data`, `domain`, `presentation`). La interfaz nunca debe acoplarse directamente a la lógica de negocio, clientes HTTP o fuentes de datos.
* **Orden y Limpieza Visual:** Ningún archivo de configuración, inyección o adaptadores debe quedar suelto en la raíz de `lib/`. Todo debe estar estrictamente agrupado en su respectiva carpeta.
* **Jerarquía de Add-ons (Estilo Stremio):** La aplicación no depende de un único proveedor fijo. Se utiliza un sistema dinámico de complementos (*add-ons*) ordenados por prioridad configurable por el usuario.
* **Adaptabilidad Multiplataforma (TV y Táctil):** Todo componente visual debe ser totalmente funcional tanto en pantallas táctiles (Android/Web) como mediante **control remoto** (teclas de dirección y selección para webOS / Smart TVs).

---

## 2. Estructura de Carpetas Obligatoria (`lib/`)

El agente debe mantener y respetar rigurosamente la siguiente jerarquía de directorios dentro de la carpeta `lib/`:

```text
lib/
├── core/
│   ├── dependencies/       # Archivos de inyección de dependencias (ej. app_dependencies.dart)
│   └── network/            # Cliente HTTP base, manejo de errores y utilidades globales
├── data/
│   ├── adapters/           # Adaptadores externos (TMDb, Torrentio, fuentes de video)
│   ├── network/            # Peticiones JSON sobre HTTP
│   ├── repositories/       # Implementaciones de persistencia y configuración local
│   └── streams/            # StreamManager (Gestor Jerárquico de ejecución de add-ons)
├── domain/
│   ├── contracts/          # Interfaces abstractas (StreamProviderContract, MediaRepository, AddonRepository)
│   ├── entities/           # Clases puras de Dart (MediaItem, StreamOption, AddonEntity, StreamRequest)
│   └── repositories/       # Definiciones de lógica de negocio y contratos puros
├── presentation/
│   ├── screens/            # Pantallas visuales (HomeScreen, AddonsConfigScreen, DetailScreen, etc.)
│   └── widgets/            # Componentes reutilizables adaptados para control remoto (FocusNode, etc.)
└── main.dart               # ÚNICO archivo suelto permitido en la raíz de lib/
```

---

## 3. Reglas Técnicas por Capa

### A. Capa de Dominio (`domain/`)
* **Independencia Total:** Prohibido importar paquetes de Flutter para UI o librerías externas de red (Dio, http, etc.). Es código de Dart puro.
* **Entidades Puras:** Clases (`MediaItem`, `StreamOption`, `AddonEntity`) que definen la estructura lógica.
* **Contratos Abstractos (`contracts/`):** Todo proveedor externo (TMDb, Torrentio o futuros add-ons) debe implementar obligatoriamente los contratos definidos aquí.

### B. Capa de Datos (`data/`)
* **Gestor Jerárquico (`StreamManager`):** Coordina múltiples fuentes de video respetando un orden de prioridad dinámico. Si un add-on falla o no arroja resultados, el gestor pasa automáticamente al siguiente de la lista configurada.
* **Almacenamiento Local:** Las preferencias de los add-ons (activos/inactivos, orden de prioridad) deben persistir localmente.

### C. Capa de Presentation (`presentation/`)
* **Diseño Visual de Streaming:** Interfaz moderna, limpia, con paleta de colores oscuros profesionales (ej. `#121212`), banners destacados (*Hero Section*) y carruseles horizontales.
* **Navegación por Control Remoto (D-Pad / TV):** 
  * Todos los botones, tarjetas y elementos interactivos deben manejar estados de enfoque (`FocusNode` o widgets enfocables).
  * Los elementos seleccionados deben mostrar claramente un borde resaltado o cambio visual para que el usuario en TV sepa exactamente dónde está ubicado.
* **Desacoplamiento:** La UI solo interactúa con los casos de uso o gestores de estado, sin conocer los detalles internos de las APIs o add-ons.

---

## 4. Restricciones de Multiplataforma (APK / IPK)
* Evitar dependencias nativas cerradas que rompan la compilación cruzada.
* Mantener la lógica agnóstica de la plataforma de destino, aislando configuraciones específicas en las carpetas nativas correspondientes (`android/`, `webos/`, etc.).