# doctor.R -------------------------------------------------------------------
#
# Herramientas para correr después de actualizar RStudio.
#
# `doctor()` revisa los .rstheme del repo y dice qué clases ofuscadas ya no
# existen en la versión instalada y cómo se llaman ahora. Reemplaza el trabajo
# de buscar los nombres a mano con el inspector del navegador.
#
# `buscar_miembro()` y `buscar_clase()` sirven para identificar un elemento
# nuevo: la primera busca por nombre semántico, la segunda traduce una clase
# ofuscada que hayas visto en el inspector.
#
# Uso:
#   source("R/clases.R"); source("R/doctor.R")
#   doctor()
#   buscar_miembro("statusBar")
#   buscar_clase("GFRCULXPQC")

#' Traduce una clase ofuscada a su nombre semántico
#'
#' Solo funciona con clases de la versión instalada de RStudio; las de
#' versiones anteriores ya no están en el bundle.
buscar_clase <- function(clase_ofuscada, mapa = mapa_clases()) {
  clase_ofuscada <- sub("^\\.", "", clase_ofuscada)
  r <- mapa[mapa$clase %in% clase_ofuscada, c("token", "clase")]
  rownames(r) <- NULL
  r
}

#' Busca nombres semánticos que contengan un texto
#'
#' Búsqueda sin distinguir mayúsculas sobre los ~1500 nombres del mapa. Útil
#' para encontrar el token de un elemento sin abrir el inspector: por ejemplo
#' `buscar_miembro("statusbar")` o `buscar_miembro("outline")`.
buscar_miembro <- function(patron, mapa = mapa_clases()) {
  r <- mapa[grepl(patron, mapa$token, ignore.case = TRUE), c("token", "clase")]
  rownames(r) <- NULL
  r
}

# Clases con forma de nombre ofuscado por GWT que aparecen en un archivo CSS.
clases_ofuscadas_en <- function(archivo, prefijos = NULL) {
  css <- paste(readLines(archivo, warn = FALSE), collapse = "\n")
  # una clase ofuscada es un selector .XXXX en mayúsculas y dígitos, largo
  # suficiente para no confundirse con clases escritas a mano
  todas <- unlist(str_extract_all(css, "(?<=\\.)[A-Z][A-Z0-9]{7,13}\\b"))
  todas <- unique(todas)
  if (!is.null(prefijos)) todas <- todas[startsWith(todas, prefijos)]
  sort(todas)
}

# Separa el prefijo del sufijo en clases ofuscadas de versiones anteriores.
#
# El prefijo de GWT no siempre mide lo mismo ("GFRCULX" tiene 7 caracteres,
# "GBQS1KEB" y "GNJ4OY0C" tienen 8), así que no se puede asumir el largo. Se
# agrupan las clases por sus primeros 6 caracteres (todo prefijo de GWT visto
# hasta ahora mide 7 o más, así que ese corte nunca parte un grupo en dos) y
# dentro de cada grupo el prefijo es el prefijo común más largo.
partir_clases <- function(clases, largo_por_defecto = 8L) {
  if (!length(clases)) return(data.frame(clase = character(), prefijo = character(),
                                         sufijo = character()))
  grupos <- split(clases, substr(clases, 1, 6))

  largos <- vapply(grupos, function(g) {
    if (length(g) < 2) NA_integer_ else nchar(prefijo_comun(g))
  }, integer(1))
  # los grupos de un solo elemento heredan el largo típico de los demás
  respaldo <- if (all(is.na(largos))) largo_por_defecto else
    as.integer(stats::median(largos, na.rm = TRUE))
  largos[is.na(largos)] <- respaldo

  do.call(rbind, lapply(names(grupos), function(g) {
    k <- largos[[g]]
    data.frame(clase = grupos[[g]],
               prefijo = substr(grupos[[g]], 1, k),
               sufijo = substr(grupos[[g]], k + 1L, nchar(grupos[[g]])),
               stringsAsFactors = FALSE)
  }))
}

# Prefijo común más largo de un vector de textos.
prefijo_comun <- function(x) {
  if (!length(x)) return("")
  chars <- strsplit(x, "", fixed = TRUE)
  ref <- chars[[1]]
  n <- min(lengths(chars))
  for (i in seq_len(n)) {
    if (!all(vapply(chars, function(c) c[i] == ref[i], logical(1)))) {
      return(paste(ref[seq_len(i - 1L)], collapse = ""))
    }
  }
  paste(ref[seq_len(n)], collapse = "")
}

#' Revisa el estado del tema frente a la versión instalada de RStudio
#'
#' Para cada .rstheme del repo informa qué clases ofuscadas siguen siendo
#' válidas, cuáles quedaron obsoletas (de versiones anteriores de RStudio, ya
#' no hacen nada) y, cuando se puede, a qué elemento correspondían.
#'
#' @param temas archivos .rstheme a revisar; por defecto los del directorio actual
#' @param fuente directorio con la fuente del tema; si existe, también se
#'   revisan los `{{tokens}}` que no resuelven
doctor <- function(temas = list.files(pattern = "\\.rstheme$"),
                   fuente = "fuente",
                   app = ruta_rstudio()) {
  m <- mapa_clases(app)
  pref <- attr(m, "prefijo")

  cat("RStudio ", attr(m, "version"), "\n", sep = "")
  cat("  ", attr(m, "app"), "\n", sep = "")
  cat("  prefijo de ofuscación: ", pref, "  (", nrow(m),
      " clases con nombre conocido)\n\n", sep = "")

  validas <- m$clase

  for (t in temas) {
    clases <- clases_ofuscadas_en(t)
    if (!length(clases)) {
      cat(t, ": sin clases ofuscadas, nada que revisar\n\n", sep = "")
      next
    }
    al_dia <- clases[clases %in% validas]
    # del prefijo actual pero sin nombre conocido: existe, solo no la resolvimos
    sin_nombre <- setdiff(clases[startsWith(clases, pref)], validas)
    obsoletas <- clases[!startsWith(clases, pref)]

    cat(t, "\n", sep = "")
    cat("  al día     : ", length(al_dia), "\n", sep = "")
    cat("  sin nombre : ", length(sin_nombre),
        if (length(sin_nombre)) paste0("  (", paste(sin_nombre, collapse = ", "), ")") else "",
        "\n", sep = "")
    cat("  OBSOLETAS  : ", length(obsoletas), "\n", sep = "")

    if (length(obsoletas)) {
      cat("\n  Estas clases son de versiones anteriores de RStudio y hoy no ",
          "aplican a nada.\n  A la derecha, la clase del mismo sufijo en la ",
          "versión actual y a qué elemento\n  corresponde. OJO: es solo una ",
          "pista. El sufijo también cambia entre versiones,\n  así que hay que ",
          "confirmarla (p. ej. GNJ4OY0CFS era ThemeResources.header,\n  pero ",
          "GFRCULXFS es ThemeResources.gutterInfo).\n\n", sep = "")
      partes <- partir_clases(obsoletas)
      partes <- partes[order(partes$prefijo, partes$sufijo), ]
      for (i in seq_len(nrow(partes))) {
        cand <- paste0(pref, partes$sufijo[i])
        pista <- m$token[match(cand, m$clase)]
        cat(sprintf("    %-14s %s\n", partes$clase[i],
                    if (is.na(pista)) "(sin candidato del mismo sufijo)"
                    else paste0(cand, " = ", pista)))
      }
    }
    cat("\n")
  }

  # tokens de la fuente que ya no resuelven
  if (dir.exists(fuente)) {
    archivos <- list.files(fuente, pattern = "\\.css$", recursive = TRUE,
                           full.names = TRUE)
    tokens <- unique(unlist(lapply(archivos, function(f) {
      txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
      str_match_all(txt, "\\{\\{([A-Za-z0-9_.$]+)\\}\\}")[[1]][, 2]
    })))
    if (length(tokens)) {
      faltan <- tokens[is.na(clase(tokens, m))]
      cat("fuente/: ", length(tokens), " tokens, ", length(faltan),
          " sin resolver\n", sep = "")
      for (tk in faltan) {
        cat("  ", tk, "\n    ", sugerencias(tk, m), "\n", sep = "")
      }
      cat("\n")
    }
  }

  invisible(NULL)
}

.cache_js <- new.env(parent = emptyenv())

# Lee el .cache.js con el CSS compilado (7 MB), cacheado por sesión.
js_rstudio <- function(app = ruta_rstudio()) {
  f <- archivo_permutacion(app)$js
  llave <- paste(f, file.mtime(f))
  if (is.null(.cache_js[[llave]])) {
    .cache_js[[llave]] <- paste(readLines(f, warn = FALSE), collapse = "\n")
  }
  .cache_js[[llave]]
}

#' Muestra el CSS que RStudio le aplica a un elemento
#'
#' Sirve para confirmar que un nombre semántico corresponde al elemento que
#' uno cree, antes de escribir una regla contra él. Es el paso que evita el
#' error clásico: los sufijos de las clases ofuscadas se desplazan entre
#' versiones, así que dos clases con el mismo sufijo en versiones distintas
#' suelen ser elementos distintos.
#'
#' @param x nombre semántico ("ThemeResources.toolbarButton") o clase
#'   ofuscada ("GFRCULXHW", con o sin punto inicial)
css_rstudio <- function(x, mapa = mapa_clases(), app = ruta_rstudio()) {
  cl <- if (grepl(".", x, fixed = TRUE)) clase(x, mapa) else sub("^\\.", "", x)
  if (is.na(cl)) {
    stop("No pude resolver '", x, "'. Usa buscar_miembro() para ver los ",
         "nombres disponibles.", call. = FALSE)
  }

  # el (?![A-Z0-9]) evita que GFRCULXHW capture también GFRCULXHWB
  rx <- paste0("[^,{}']{0,90}\\.", cl, "(?![A-Z0-9])[^,{}']{0,25}\\{[^}]{0,250}\\}")
  reglas <- unique(unlist(str_extract_all(js_rstudio(app), rx)))

  cat(x, " -> .", cl, "\n", sep = "")
  if (!length(reglas)) {
    cat("  (RStudio no le aplica ninguna regla propia)\n")
  } else {
    for (r in reglas) cat("  ", str_trim(r), "\n", sep = "")
  }
  invisible(reglas)
}
