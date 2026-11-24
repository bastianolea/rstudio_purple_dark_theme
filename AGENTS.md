# AGENTS.md

Tema para RStudio. Los `.rstheme` **se generan**; la fuente está en `fuente/`.

## Regla principal

**Nunca editar un `.rstheme` directamente.** Se sobrescriben en cada build. Todo
cambio va a `fuente/<tema>/*.css` y después se corre `construir_tema()`.

Tampoco editar `fuente/dark/02-editor.css`, `03-ide.css` ni `04-terminal.css`:
son salida de `{rsthemes}` y se conservan intactas para poder regenerarlas. Los
overrides sobre esos bloques van en `05-estable.css`, marcados con `OVERRIDE`.

## Estructura

```
fuente/dark/01-cabecera.css   metadata (rs-theme-name, rs-theme-is-dark)
fuente/dark/02-editor.css     ace / sintaxis        (generado, no editar)
fuente/dark/03-ide.css        chrome básico         (generado, no editar)
fuente/dark/04-terminal.css   paleta xterm          (generado, no editar)
fuente/dark/05-estable.css    parches con clases estables de RStudio
fuente/dark/06-chrome.css     parches con {{nombres.semanticos}}
fuente/light/                 igual, con 02-base.css unificado

R/clases.R   ruta_rstudio, archivo_permutacion, mapa_clases, clase
R/construir.R     construir_tema, resolver_tokens, renombrar_tema, validar_css
R/doctor.R        doctor, buscar_clase, buscar_miembro, css_rstudio
```

`construir_tema()` concatena los `.css` en orden alfabético (el prefijo numérico
fija la cascada), resuelve los tokens y valida antes de escribir.

## El problema que resuelve este repo

RStudio se compila con GWT, que ofusca las clases CSS de su propia interfaz
(`GFRCULXJX`). El nombre cambia en cada release, así que los parches al chrome
del IDE —bordes de paneles, barra de estado, panel de entorno, diálogos,
outline— se rompían en cada actualización. No hay API para eso; el contrato
público de temas cubre solo `.ace_*`, `.xterm*`, `.rstudio-themes-*`,
`.rstheme_*`, `.gwt-*`, `#rstudio_*` y atributos ARIA / `data-slot`.

El mapa nombre semántico → clase ofuscada se extrae de la instalación de
RStudio cruzando dos archivos que Posit sí envía:

1. `www-symbolmaps/<hash>.symbolMap` (desde 2026.10 viene comprimido como
   `.symbolMap.gz`; `archivo_permutacion()` acepta ambos), campos
   `simbolo,jsniIdent,claseJava,miembro,archivo,linea,fragmento`. Interesan las
   líneas con `ClientBundleGenerator` en la clase y `()Ljava/lang/String;` en el
   jsniIdent.
2. `www/rstudio/<mismo-hash>.cache.js`, donde ese símbolo aparece como
   `function xJf(){return OXv}` y la tabla de strings define `OXv='GFRCULXJX'`.

Solo una de las ~15 permutaciones `.cache.js` lleva el CSS; se identifica por
contener `rstheme_toolbarWrapper`. El prefijo de ofuscación es único por
compilación pero su largo varía (7 en `GFRCULX`, 8 en `GBQS1KEB`, `GNJ4OY0C` y
`GCOP2I3B`), así que se detecta por frecuencia, no se asume.

Cobertura del mapa: 1546 de 1661 clases en 2026.07.1; 1552 clases nombradas en
2026.10.0+233 (hash de permutación `C8599449...`, prefijo `GCOP2I3B`).

## Después de actualizar RStudio

`aplicar.R` es el flujo normal (`construir_tema(..., instalar = TRUE)` para
`dark` y `light`). Si falla:

1. **Revisar primero el formato de los archivos que Posit envía**, antes de
   suponer que falta algo. En 2026.10 el error "Falta .../www-symbolmaps"
   era engañoso: la carpeta existía, pero el archivo pasó de `.symbolMap` a
   `.symbolMap.gz` y el código solo buscaba el nombre plano. Comprobar con
   `ls www-symbolmaps` y `ls www/rstudio` bajo `ruta_rstudio()`.
2. Correr `doctor()`. Las clases literales (con punto delante) que ya no
   existen salen como OBSOLETAS; si el sufijo sigue existiendo, **no
   reasignarlo**: casi siempre es otro elemento (ver "Trampa principal").
3. Reglas con clase literal que no se pueden renombrar: desactivarlas
   comentadas con el motivo (convención abajo), no adivinar.

## Trampa principal

**Los sufijos de las clases ofuscadas se desplazan entre versiones.** Nunca
asumir que `GNUEVO<sufijo>` es el mismo elemento que `GVIEJO<sufijo>`.
Contraejemplos verificados en este repo:

- `GNJ4OY0CFS` era `ThemeResources.header`; `GFRCULXFS` es
  `ThemeResources.gutterInfo`.
- El parche del botón de modo visual usaba la clase del toolbar en la posición
  del botón: los cuatro sufijos de la cadena se habían corrido una posición.

Antes de escribir una regla contra un nombre semántico, confirmarlo con
`css_rstudio("Recurso.miembro")`, que imprime el CSS propio de RStudio para esa
clase. Si las declaraciones no cuadran con el elemento, el nombre está mal.

`doctor()` sugiere candidatos del mismo sufijo, pero los marca explícitamente
como pista a confirmar, no como respuesta.

## Trampa: los `#rstudio_*` no son el elemento que se pinta

Los ids `#rstudio_*` son el selector más estable que hay, pero casi nunca están
sobre el elemento que tiene el borde o el fondo. Muchos widgets de RStudio son
un `Composite` cuyo `HTMLPanel` de GWT agrega un `<div>` contenedor propio: el
id (y las clases que el código Java agrega con `addStyleName`) caen en ese
contenedor invisible, y la caja visible es su hijo. Si se le pone fondo o borde
al elemento del id aparece un segundo cuadro alrededor del control.

Ejemplo verificado, el buscador "Go to file/function" de la barra de menú:

```html
<div id="rstudio_code_search_widget" class="{{CodeSearchResources.codeSearchWidget}}">
  <div class="search">                      <!-- la caja: borde y alto -->
    <div class="{{ThemeResources.left}}">    <!-- extremo de 6px, fondo propio -->
    <div class="rstheme_center">             <!-- el relleno, detrás del texto -->
    <div class="{{ThemeResources.right}}">   <!-- display:none dentro de .search -->
```

Dos señales para detectarlo sin abrir el inspector:

- Si `css_rstudio()` devuelve reglas propias de RStudio con combinador de
  descendencia (`.GFRCULXDTB .search {...}`), la clase del widget está en un
  ancestro, no en el elemento estilado.
- La plantilla UiBinder se puede reconstruir del `.cache.js`: la función que
  arma el HTML concatena trozos literales (`MBv="<div class='"`,
  `PBv="'> <div class='"`, ...) con los accesores de estilo. Buscar la función
  que recibe `styles.<algo>()` y resolver esos trozos da el DOM exacto.

Corolario para escribir reglas: apuntar el borde y el fondo a los hijos
(`#id .search`, `#id .search > div`) y dejar el elemento del id sin pintar. El
`#id` sirve para acotar el alcance —los buscadores del IDE comparten `.search`
y `.rstheme_center`— y además gana en especificidad (1-1-0) contra los
`!important` de los bloques generados (0-3-0), que solo usan clases.

## Convenciones

- Comentarios y nombres de funciones en español.
- En `05-estable.css` y `06-chrome.css`: un comentario por regla describiendo
  qué elemento arregla; lo más nuevo al final.
- Las reglas recuperadas de versiones anteriores se marcan `RECUPERADA:` con el
  motivo, para poder revisarlas a ojo y revertirlas.
- Las reglas desactivadas se dejan comentadas con su motivo, no se borran.
- Los comentarios de la fuente CSS no deben escribir una clase ofuscada con
  punto delante (`.GXXXXXXX`): `doctor()` extrae `(?<=\.)[A-Z][A-Z0-9]{7,13}`
  del CSS sin ignorar comentarios y la reportaría como obsoleta. Nombrar la
  clase sin punto. Los ejemplos de versiones viejas en los comentarios de
  cabecera tampoco deben llevar prefijos de una versión anterior.
- Los temas generados llevan sufijo `-2` en el archivo y en `rs-theme-name`,
  para convivir con los `.rstheme` anteriores hechos a mano (que se conservan
  solo como referencia y están rotos en 2026.07+). Se cambia con
  `construir_tema(..., sufijo = "")`.

## Entorno

- RStudio está en `~/Applications/RStudio.app`, **no** en `/Applications`.
  `ruta_rstudio()` prueba varias rutas y el ancla `RSTUDIO_PANDOC`; se puede
  forzar con `options(basti.rstudio_path = ...)`.
- Dependencias: `stringr`, `rstudioapi`. `rsthemes` no está instalado y no hace
  falta.
- `mapa_clases()` y `js_rstudio()` cachean por sesión: parsear el `.cache.js`
  de 7 MB toma unos segundos.
- `construir_tema(instalar = TRUE)` necesita RStudio corriendo (usa
  `rstudioapi`); desde `Rscript` falla con "RStudio not running". Para
  verificar un cambio en la terminal, construir sin instalar.
- El asistente no puede instalar el tema: copiar a `~/.config/rstudio/themes`
  queda bloqueado por el sandbox del agente ("Path is not within the project").
  El agente construye y verifica con `doctor()` sin `instalar`; el usuario
  corre `aplicar.R` desde su propia sesión de RStudio para aplicar el tema.
- Los `.rstheme` de la raíz del repo son salida del build: cambian en cada
  `construir_tema()`, incluso sin instalar.

## Pendientes conocidos

- La regla de la ventana de "session aborted" (clase literal `GFRCULXPAB`, la
  única que el mapa nunca supo nombrar) quedó desactivada en 2026.10.0 porque
  la clase desapareció y el sufijo `PAB` ahora es otro elemento. Hay que
  reescribirla con nombre semántico: provocar la ventana y leer la clase en el
  inspector. Solo cambiaba `color: #141414` en esa ventana; la declaración
  original está en el comentario de `06-chrome.css`.
- Los bordes de paneles y la barra de estado se unificaron en `#111111`,
  tomando la intención del último cambio hecho a mano. Antes solo algunas ramas
  del selector recibían ese valor y el resto quedaba en `rgb(22,22,22)`.
- Dos reglas quedaron desactivadas a propósito, documentadas en la fuente: el
  borde de los popups de menú (estaba escrita `border: #404040`, CSS inválido)
  y ocultar los separadores de la barra de herramientas (estaba dentro de un
  comentario sin cerrar).
- Sin implementar: resolución por huella de las declaraciones, para
  instalaciones sin `www-symbolmaps` (RStudio Server o instalaciones
  recortadas). Hoy `mapa_clases()` falla con un mensaje claro en ese caso.

## Flujo para pedidos de cambios al tema

Los pedidos típicos son del tipo "tal elemento se ve sin tema", "este borde
debería ser #151515" o "esto debería tener el color de aquello". El usuario
suele pegar las clases o el HTML del elemento, copiados del inspector. El flujo:

1. **Identificar de qué parte viene el elemento**, porque cada una se
   resuelve de otra forma:

   | Origen               | Señales en las clases                  | Selector a usar             |
   |----------------------|----------------------------------------|-----------------------------|
   | Editor (ace)         | `ace_*`                                | `.ace_*`                    |
   | Chrome GWT           | `GXXXXXXX..` ofuscadas, `gwt-*`        | `{{Recurso.miembro}}`, ids  |
   | Posit Assistant      | Tailwind (`flex`, `px-1`, `bg-muted`…) | `[data-slot=...]`, ARIA     |
   | Terminal             | `xterm*`                               | `.xterm*`                   |

2. **Buscar un selector estable, nunca usar las clases pegadas tal cual**
   (salvo las de la lista pública del contrato de temas).
   - Chrome GWT: `buscar_clase("GXXXXXXXJX")` da el nombre semántico,
     `buscar_miembro("patron")` busca por nombre y `css_rstudio("Recurso.miembro")`
     confirma con el CSS propio de RStudio que es el elemento correcto. Tener
     en cuenta las trampas de arriba (sufijos que se desplazan, `#rstudio_*`
     que no son la caja visible).
   - Posit Assistant: ver la sección siguiente.

3. **Escribir la regla en la fuente**: `05-estable.css` si usa selectores
   estables (ids, `data-slot`, `gwt-*`) y `06-chrome.css` si usa tokens
   `{{...}}`. Un comentario por regla que diga qué elemento arregla y, si no es
   obvio, por qué la regla es así. Lo nuevo va al final del bloque relacionado.
   Solo tocar `fuente/light/` si el pedido es para el tema claro.

4. **Construir y verificar** con el bloque de la sección "Verificación" (abajo).
   Basta con construir el tema que se tocó. El agente no puede instalar: al
   terminar, decirle al usuario que corra `aplicar.R` y que no se ha visto el
   resultado en pantalla.

5. **Iterar con lo que el usuario ve.** El primer intento rara vez queda
   perfecto. Con cada corrección, ajustar la regla existente en vez de agregar
   otra que la contradiga.

### Posit Assistant

La interfaz de Posit Assistant es una app web (React + Tailwind) que corre
dentro de RStudio. El `.rstheme` se inyecta también ahí, así que se puede
tematizar desde `05-estable.css`. En modo oscuro su raíz lleva la clase
`.dark`, que sirve de prefijo para todas sus reglas.

- **No usar las clases de Tailwind** (`bg-muted/30`, `px-1`…): cambian
  con cada versión del asistente y además se comparten entre muchos elementos.
  Usar `data-slot`, `data-state`, `data-testid`, `role` o `aria-label`.
- **El bundle está en disco** y es la forma más rápida de ver el DOM real,
  sin pedirle al usuario que abra el inspector:

  ```bash
  ls ~/.local/share/rstudio/pai/versions/            # usar la más reciente
  grep -l "texto-de-una-clase" ~/.local/share/rstudio/pai/versions/<ver>/dist/client/*.js
  ```

  El `.js` está minificado en una línea, así que `grep -o` con contexto largo
  falla. Para extraer un fragmento alrededor de una clase pegada por el
  usuario, usar Python:

  ```bash
  python3 -c "s=open('main.XXXX.js').read(); i=s.find('conversation-tabs-viewport'); print(s[i-2500:i+3000])"
  ```

  En el JSX compilado se ven los `className` de cada rama (seleccionada / no
  seleccionada, horizontal / vertical) y los atributos `data-slot` y
  `data-state` del elemento.
- **El elemento que pega el usuario suele ser un contenedor.** Muchos
  componentes tienen un envoltorio invisible (`role="presentation"`, `absolute
  inset-0`, `electrobun-webkit-app-region-*`) y la caja visible es un hijo con
  `data-slot`. Confirmarlo en el bundle.
- **Fijarse en cómo Tailwind dibuja cada cosa**, porque la regla tiene que
  actuar sobre lo mismo:
  - Líneas como `shadow-[inset_0_-1px_0_var(--border)]` son `box-shadow`, no
    bordes: se reemplazan con `box-shadow`.
  - `before:`/`after:` son pseudo-elementos: un velo `before:bg-foreground/4`
    se pinta sobre `::before` y tapa el fondo del elemento, así que hay que
    reemplazarlo ahí también. Los `hover:before:` se pierden al poner un
    color sólido: reponer el hover con `:hover::before`.
  - `border-transparent` o `border-x border-t` explican bordes faltantes:
    Posit cuenta con que otra capa dibuje esa línea, y al poner fondos sólidos
    hay que dibujarla en el elemento.
- Las utilidades de Tailwind tienen especificidad baja, pero algunas vienen
  con variables CSS y estados. Usar `!important` en estas reglas, como en las
  existentes.
- Paleta usada para imitar RStudio en el tema oscuro:

  | Elemento                                        | Color     |
  |-------------------------------------------------|-----------|
  | Barra de pestañas y pestañas no seleccionadas   | `#282828` |
  | Pestaña seleccionada y barra superior (topbar)  | `#383838` |
  | Hover de pestaña no seleccionada                | `#303030` |
  | Fondo del panel de conversación                 | `#181818` |
  | Líneas divisorias                               | `#111111` |
  | Borde de pestañas no seleccionadas              | `#151515` |

## Verificación después de tocar la fuente

```r
source("R/clases.R"); source("R/construir.R"); source("R/doctor.R")
construir_tema("dark"); construir_tema("light")
doctor()   # debe dar OBSOLETAS: 0 y 0 tokens sin resolver en los temas -2
```

Para un cambio grande, comparar reglas contra el `.rstheme` anterior
normalizando espacios y comentarios: el diff debe contener solo lo intencional.
