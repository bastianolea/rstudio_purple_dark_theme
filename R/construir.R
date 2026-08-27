# construir.R ----------------------------------------------------------------
#
# Genera los archivos .rstheme a partir de fuente/<tema>/*.css.
#
# Los archivos de fuente/ se concatenan en orden alfabético (por eso llevan
# prefijo numérico) y los nombres semánticos escritos entre llaves dobles se
# reemplazan por las clases ofuscadas de la versión de RStudio instalada.
#
#   fuente/dark/01-cabecera.css   metadata del .rstheme
#   fuente/dark/02-editor.css     resaltado de sintaxis (generado, no editar)
#   fuente/dark/03-ide.css        chrome básico (generado, no editar)
#   fuente/dark/04-terminal.css   paleta del terminal (generado, no editar)
#   fuente/dark/05-estable.css    parches con clases estables
#   fuente/dark/06-chrome.css     parches con {{nombres.semanticos}}
#
# Uso:
#   source("R/mapa-clases.R"); source("R/construir.R")
#   construir_tema("dark", instalar = TRUE)

if (!exists("mapa_clases")) source(file.path("R", "mapa-clases.R"))

TOKEN_RX <- "\\{\\{([A-Za-z0-9_.$]+)\\}\\}"

#' Genera un .rstheme desde su fuente
#'
#' @param tema "dark" o "light"; también es el nombre del subdirectorio de fuente/
#' @param sufijo se agrega al nombre del archivo y al nombre que RStudio muestra
#'   en Appearance, para poder tener instalado el tema generado junto al
#'   anterior hecho a mano sin que se pisen. Con `sufijo = ""` se generan
#'   `basti-purple-dark.rstheme` / "Basti Purple Dark", como antes.
#' @param salida archivo a escribir; por defecto basti-purple-<tema>-<sufijo>.rstheme
#' @param instalar si TRUE, instala el tema en RStudio y lo aplica
#' @param estricto si TRUE (recomendado para uso propio) falla cuando un nombre
#'   no resuelve. Si FALSE, avisa y omite las reglas afectadas, de modo que el
#'   tema salga usable igual: pierde ese detalle del chrome pero no se rompe.
#'   Útil para generar un tema que otras personas usarán en otras versiones.
construir_tema <- function(tema = c("dark", "light"),
                           sufijo = "2",
                           salida = NULL,
                           instalar = FALSE,
                           estricto = TRUE,
                           app = ruta_rstudio()) {
  tema <- match.arg(tema)
  dir_fuente <- file.path("fuente", tema)
  if (!dir.exists(dir_fuente)) {
    stop("No existe ", dir_fuente, call. = FALSE)
  }
  if (is.null(salida)) {
    salida <- paste0("basti-purple-", tema,
                     if (nzchar(sufijo)) paste0("-", sufijo) else "", ".rstheme")
  }

  archivos <- sort(list.files(dir_fuente, pattern = "\\.css$", full.names = TRUE))
  if (!length(archivos)) stop("No hay archivos .css en ", dir_fuente, call. = FALSE)

  partes <- lapply(archivos, function(f) paste(readLines(f, warn = FALSE), collapse = "\n"))

  m <- mapa_clases(app)

  # El aviso va DESPUÉS del primer archivo: RStudio busca la metadata
  # (rs-theme-name, rs-theme-is-dark) al principio del .rstheme, así que la
  # cabecera tiene que seguir siendo lo primero del archivo.
  aviso <- sprintf(
    paste0("/* Generado por construir_tema(\"%s\") desde fuente/%s/ — no editar a mano. */\n",
           "/* RStudio %s, prefijo de ofuscación %s. */"),
    tema, tema, attr(m, "version"), attr(m, "prefijo"))
  partes <- append(partes, list(aviso), after = 1)

  css <- paste(unlist(partes), collapse = "\n\n")
  css <- renombrar_tema(css, sufijo)
  css <- resolver_tokens(css, m, estricto = estricto)
  validar_css(css)

  writeLines(css, salida, useBytes = TRUE)
  message("Escrito ", salida, "  (\"", nombre_tema(css), "\", ",
          length(strsplit(css, "\n")[[1]]), " líneas)")

  if (instalar) {
    rstudioapi::addTheme(salida, apply = TRUE, force = TRUE)
    message("Instalado y aplicado en RStudio")
  }

  invisible(salida)
}

RX_NOMBRE <- "(/\\*\\s*rs-theme-name:\\s*)(.*?)(\\s*\\*/)"

# Nombre que RStudio va a mostrar en Appearance.
nombre_tema <- function(css) str_match(css, RX_NOMBRE)[, 3]

# Agrega el sufijo al nombre del tema. Es lo que permite tener instalado el
# tema generado junto al anterior hecho a mano: si solo cambiara el nombre del
# archivo, RStudio mostraría los dos con el mismo nombre y uno pisaría al otro.
renombrar_tema <- function(css, sufijo) {
  if (!nzchar(sufijo)) return(css)
  if (!str_detect(css, RX_NOMBRE)) {
    stop("La fuente no declara /* rs-theme-name: ... */, así que no se puede ",
         "agregar el sufijo \"", sufijo, "\".", call. = FALSE)
  }
  str_replace(css, RX_NOMBRE, paste0("\\1\\2 ", sufijo, "\\3"))
}

# Reemplaza {{Recurso.miembro}} por la clase ofuscada correspondiente.
resolver_tokens <- function(css, mapa, estricto = TRUE) {
  usados <- unique(str_match_all(css, TOKEN_RX)[[1]][, 2])
  if (!length(usados)) return(css)

  clases <- clase(usados, mapa)
  faltan <- usados[is.na(clases)]

  if (length(faltan)) {
    detalle <- vapply(faltan, function(tk) {
      paste0("  ", tk, "\n    ", sugerencias(tk, mapa))
    }, character(1))

    aviso <- paste0(
      length(faltan), " nombre(s) no resuelven en RStudio ", attr(mapa, "version"), ":\n",
      paste(detalle, collapse = "\n"), "\n",
      "Usa buscar_miembro() para encontrar el nombre nuevo, o doctor() para el panorama completo.")

    if (estricto) stop(aviso, call. = FALSE)

    warning(aviso, "\nSe omiten las reglas que los usan (estricto = FALSE).", call. = FALSE)
    css <- omitir_reglas_con_tokens(css, faltan)
    usados <- setdiff(usados, faltan)
    clases <- clase(usados, mapa)
  }

  for (i in seq_along(usados)) {
    css <- gsub(paste0("{{", usados[i], "}}"), clases[i], css, fixed = TRUE)
  }
  css
}

# Nombres parecidos a uno que no resolvió, para sugerir el reemplazo.
# Primero busca en el mismo recurso; si el recurso desapareció, busca en todo
# el mapa por el nombre del miembro.
sugerencias <- function(token, mapa, n = 6L) {
  recurso <- sub("\\..*$", "", token)
  miembro <- sub("^.*\\.", "", token)
  del_recurso <- mapa$token[mapa$recurso == recurso]

  if (!length(del_recurso)) {
    candidatos <- mapa$token[mapa$miembro == miembro]
    if (length(candidatos)) {
      return(paste0("el recurso ", recurso, " ya no existe; hay un miembro '",
                    miembro, "' en: ", paste(head(candidatos, n), collapse = ", ")))
    }
    candidatos <- mapa$token
    cerca <- candidatos[order(utils::adist(token, candidatos))][seq_len(min(n, length(candidatos)))]
    return(paste0("el recurso ", recurso, " ya no existe. Parecidos: ",
                  paste(cerca, collapse = ", ")))
  }

  cerca <- del_recurso[order(utils::adist(token, del_recurso))]
  paste0(recurso, " existe pero no tiene '", miembro, "'. Parecidos: ",
         paste(head(cerca, n), collapse = ", "),
         if (length(cerca) > n) paste0(" (y ", length(cerca) - n, " más; ",
                                       "usa buscar_miembro())") else "")
}

# Borra las reglas CSS que usan alguno de los tokens dados. Se hace a nivel de
# regla completa para no dejar CSS a medio escribir. Los tokens se enmascaran
# antes de cortar porque terminan en '}}' y romperían el corte por llaves.
omitir_reglas_con_tokens <- function(css, tokens) {
  enmascarado <- gsub(TOKEN_RX, "\u0001\\1\u0002", css)
  reglas <- str_split(enmascarado, "(?<=\\})")[[1]]
  marcas <- paste0("\u0001", tokens, "\u0002")
  malas <- vapply(reglas, function(r) {
    any(vapply(marcas, function(mk) grepl(mk, r, fixed = TRUE), logical(1)))
  }, logical(1))
  limpio <- paste(reglas[!malas], collapse = "")
  gsub("\u0001([A-Za-z0-9_.$]+)\u0002", "{{\\1}}", limpio)
}

# Comprobaciones baratas que atrapan los errores que ya nos han morddo:
# comentarios sin cerrar, llaves desbalanceadas y tokens sin resolver.
validar_css <- function(css) {
  problemas <- character()

  abre <- str_count(css, fixed("/*"))
  cierra <- str_count(css, fixed("*/"))
  if (abre != cierra) {
    problemas <- c(problemas, sprintf(
      "comentarios desbalanceados: %d '/*' y %d '*/' (un comentario sin cerrar se ",
      abre, cierra))
    problemas <- c(problemas,
      "  come las reglas que vienen después sin avisar")
  }

  # las llaves de dentro de comentarios no cuentan
  sin_comentarios <- gsub("/\\*.*?\\*/", "", css)
  if (str_count(sin_comentarios, fixed("{")) != str_count(sin_comentarios, fixed("}"))) {
    problemas <- c(problemas, sprintf("llaves desbalanceadas: %d '{' y %d '}'",
                                      str_count(sin_comentarios, fixed("{")),
                                      str_count(sin_comentarios, fixed("}"))))
  }

  restantes <- str_match_all(css, TOKEN_RX)[[1]]
  if (nrow(restantes)) {
    problemas <- c(problemas, paste0("quedaron tokens sin resolver: ",
                                     paste(unique(restantes[, 1]), collapse = ", ")))
  }

  if (length(problemas)) {
    stop("El CSS generado no pasó la validación:\n  ",
         paste(problemas, collapse = "\n  "), call. = FALSE)
  }
  invisible(TRUE)
}
