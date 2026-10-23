# Editor de Video (Mac + iPhone)

Editor de video al estilo CapCut, escrito en Swift con SwiftUI y AVFoundation. Un solo proyecto
compila para **macOS 14+** y **iOS 17+** (iPhone y iPad).

## Qué puede hacer (versión 1)

| Función | Cómo |
|---|---|
| Importar videos | Botón **Fotos** (biblioteca de Fotos) o **Archivo** (Finder / app Archivos). Se pueden agregar varios clips seguidos. |
| Cortar (recortar) | Selecciona un clip en la línea de tiempo → **Recortar** → mueve inicio y fin. |
| Dividir | Coloca el cabezal rojo (arrastra sobre la regla o usa el control deslizante) → **Dividir**. |
| Reordenar / duplicar / eliminar clips | Botones **Atrás**, **Adelante**, **Duplicar**, **Eliminar** sobre el clip seleccionado. |
| Texto | **Texto** → escribe, elige tamaño, color, momento y duración. Arrastra el texto sobre la vista previa para ubicarlo. |
| Audio | **Audio** → silenciar o bajar el audio original, agregar música o voz desde un archivo, ajustar volumen y punto de inicio. |
| Transiciones | Selecciona un clip → **Transición** → fundido cruzado, fundido a negro, deslizar, zoom o barrido, con duración ajustable. |
| Efectos / filtros | **Filtro** → blanco y negro, noir, sepia, vívido, cálido, frío, desvanecido, chrome, instantánea. |
| Exportar | **Exportar** → formato **MP4 o MOV**, códec **H.264 o HEVC (H.265)**, resolución **original / 480p / 720p / 1080p / 4K** y calidad **alta / media / baja**. En iPhone se guarda en Fotos; en Mac con "Guardar como…". En ambos se puede **Compartir**. |

La vista previa reproduce exactamente lo que se va a exportar (transiciones, filtro y mezcla de
audio incluidos). Los textos se muestran sobre la vista previa y se "queman" en el video al exportar.

## Cómo compilar y ejecutar

### Requisitos
- Un Mac con **Xcode 16 o superior** (gratis en la Mac App Store).
- Para el iPhone: cable USB (o Wi‑Fi tras el primer emparejamiento) y un Apple ID. No hace falta
  pagar el programa de desarrolladores para instalarlo en tu propio teléfono.

### 1. Abrir el proyecto
1. Descarga o clona esta carpeta.
2. Haz doble clic en `VideoEditor.xcodeproj`.

### 2. Firmar con tu Apple ID (solo la primera vez)
1. En Xcode: menú **Xcode → Settings… → Accounts → +** y agrega tu Apple ID.
2. En el navegador de la izquierda haz clic en el proyecto **VideoEditor** (ícono azul) →
   pestaña **Signing & Capabilities**.
3. En **Team** elige tu nombre (Personal Team).
4. Si Xcode se queja de que el *Bundle Identifier* ya está en uso, cámbialo por algo único, por
   ejemplo `com.tunombre.VideoEditor`.

### 3. Ejecutar en el Mac
1. Arriba, en el selector de destino (al lado del botón ▶), elige **My Mac**.
2. Pulsa ▶ (o `⌘R`). La app se abre como una ventana normal de macOS.

### 4. Instalar en el iPhone
1. Conecta el iPhone con el cable y desbloquéalo. Si pregunta "¿Confiar en este ordenador?", acepta.
2. En el iPhone activa el **Modo de desarrollador**: Ajustes → Privacidad y seguridad →
   Modo de desarrollador → activar (reinicia el teléfono).
3. En Xcode elige tu iPhone en el selector de destino y pulsa ▶.
4. La primera vez iOS bloquea la app: ve a Ajustes → General → **VPN y gestión de dispositivos**
   → toca tu Apple ID → **Confiar**. Vuelve a abrir la app.

> Con una cuenta gratuita la app instalada en el iPhone caduca a los **7 días**; basta con volver a
> pulsar ▶ desde Xcode para renovarla. Con el programa de desarrolladores de pago (99 USD/año) dura
> un año y además podrías distribuirla por TestFlight.

### Consejos
- Si Xcode muestra un error de compilación en `TransitionCompositor.swift` en la línea de
  `sourcePixelBufferAttributes`, cambia el tipo `[String: any Sendable]` por `[String: Any]` (el tipo
  exacto depende de la versión del SDK).
- Exportar en 4K o con HEVC es más lento; en un iPhone antiguo puede tardar varios minutos.
- Los archivos importados se copian dentro de la app (carpeta `Application Support/VideoEditor/Media`),
  así que puedes borrar los originales sin perder el proyecto mientras la app esté abierta.

## Estructura del código

```
VideoEditor/
├── VideoEditorApp.swift          Punto de entrada
├── Models/
│   ├── Models.swift              Clip, texto, pista de audio, transiciones, filtros, línea de tiempo
│   └── EditorModel.swift         Estado del editor y todas las operaciones (dividir, recortar, etc.)
├── Engine/
│   ├── CompositionBuilder.swift  Arma la AVComposition, instrucciones de video, mezcla de audio y textos
│   ├── TransitionCompositor.swift Compositor personalizado (rotación, transiciones, filtros con Core Image)
│   ├── Exporter.swift            Opciones de exportación y AVAssetExportSession
│   └── MediaStore.swift          Copia de archivos importados, miniaturas, soporte para PhotosPicker
└── Views/
    ├── EditorView.swift          Pantalla principal, barra de herramientas, importación
    ├── PreviewView.swift         Reproductor y textos arrastrables
    ├── TimelineView.swift        Línea de tiempo con miniaturas, textos y audio
    └── Sheets.swift              Hojas: recortar, transición, texto, audio, filtro, exportar
```

## Próximos pasos posibles
- Guardar y reabrir proyectos.
- Velocidad (cámara lenta / rápida) y volumen por clip.
- Stickers, fuentes adicionales y animaciones de texto.
- Recorte de encuadre (crop) y relación de aspecto 9:16 / 1:1 para redes.
- Extracción de audio de un video para usarlo en otro.
