SPECIAL_FUNCTIONS = expression(
    to_list,
    to_vec,
    alter ,
    to_df ,
    to_dfr,
    to_dfc,
    comprehenr::to_list,
    comprehenr::to_vec ,
    comprehenr::alter  ,
    comprehenr::to_df  ,
    comprehenr::to_dfr ,
    comprehenr::to_dfc
)


#' List comprehensions for R
#'
#' - `to_list` converts usual R loops expressions to list producers.
#' Expression should be started with `for`, `while` or
#' `repeat`. You can iterate over multiple lists if you provide several
#' loop variables in backticks. See examples.
#' - `to_vec` is the same as 'to_list' but return vector. See examples.
#' - `to_df` is the same as 'to_list' but return data.frame. All elements of
#' resulted list will be converted to data.frame and combined via `rbind`.
#' - `alter` returns the same type as its argument but with modified
#' elements. It is useful for altering existing data.frames or lists. See
#' examples.
#' - `exclude` is an auxiliary function for dropping elements in
#' `alter`. There are no arguments for this function.
#'
#' @param expr expression which starts with `for`, `while` or `repeat`.
#' @param recursive	logical. Should unlisting be applied to list components of result? See [unlist][base::unlist] for details.
#' @param use.names logical. Should names be preserved? See [unlist][base::unlist] for details.
#' @param fill logical. TRUE by default. Should we combine data.frames with different names in the `to_df`?
#' @param data data.frame/list/vector which we want to alter
#' @return list for `to_list` and vector for `to_vec`
#' @export
#'
#' @examples
#' # rather useless expression - squares of even numbers
#' to_list(for(i in 1:10) if(i %% 2==0) i*i)
#'
#' # Pythagorean triples
#' to_list(for (x in 1:30) for (y in x:30) for (z in y:30) if (x^2 + y^2 == z^2) c(x, y, z))
#'
#' colours = c("red", "green", "yellow", "blue")
#' things = c("house", "car", "tree")
#' to_vec(for(x in colours) for(y in things) paste(x, y))
#'
#' # prime numbers
#' noprimes = to_vec(for (i in 2:7) for (j in seq(i*2, 99, i)) j)
#' primes = to_vec(for (x in 2:99) if(!x %in% noprimes) x)
#' primes
#'
#' # iteration over multiple lists
#' to_vec(for(`i, j` in numerate(letters)) if(i %% 2==0) paste(i, j))
#'
#' set.seed(123)
#' rand_sequence = runif(20)
#' # gives only locally increasing values
#' to_vec(for(`i, j` in lag_list(rand_sequence)) if(j>i) j)
#'
#' # to_df
#' to_df(for(`name, x` in mark(mtcars)) list(mean = mean(x), sd = sd(x), var = name))
#'
#' # 'alter' examples
#' data(iris)
#' # scale numeric variables
#' res = alter(for(i in iris) if(is.numeric(i)) scale(i))
#' str(res)
#'
#' # convert factors to characters
#' res = alter(for(i in iris) if(is.factor(i)) as.character(i))
#' str(res)
#'
#' # exclude factors from data.frame
#' res = alter(for(i in iris) if(is.factor(i)) exclude())
#' str(res)
#'
#' # 'data' argument example
#' # specify which columns to map with a numeric vector of positions:
#' res = alter(
#'     for(`i, value` in numerate(mtcars)) if(i %in% c(1, 4, 5)) as.character(value),
#'     data = mtcars
#' )
#' str(res)
#'
#' # or with a vector of names:
#' res = alter(
#'     for(`name, value` in mark(mtcars)) if(name %in% c("cyl", "am")) as.character(value),
#'     data = mtcars
#' )
#' str(res)
to_list = function(expr){
    expr = substitute(expr)
    is_loop(expr) ||
        stop(paste("argument should be expression with 'for', 'while' or 'repeat' but we have: ", deparse(expr, width.cutoff = 500)[1]))


    expr = expand_loop_variables(expr)
    expr = add_assignment_to_final_loops(expr)

    expr = substitute(local({
        .___res <- list()
        .___counter <- 0  # initial list length
        expr
        .___res
    }))

    eval.parent(expr)

}

#' @export
#' @rdname to_list
to_vec = function(expr, recursive = TRUE, use.names = FALSE){
    res= eval.parent(substitute(comprehenr::to_list(expr)))
    unlist(res, recursive = recursive, use.names = use.names)
}


add_assignment_to_final_loops = function(expr, result_exists = FALSE){
    if(is_loop(expr)){
        if(has_loop_inside(expr[-1])){
            expr[-1] = as.call(lapply(as.list(expr)[-1], add_assignment_to_final_loops, result_exists = result_exists))
        } else {
            expr = add_assignment_to_loop(expr, result_exists = result_exists)
        }
    } else {
        if(has_loop_inside(expr)){
            expr = as.call(lapply(as.list(expr), add_assignment_to_final_loops, result_exists = result_exists))
        }
    }
    expr
}

expand_loop_variables = function(expr){
    if(!is.call(expr)) return(expr)
    if(is_for_loop(expr)){
            expr = add_expansion_to_loop(expr)
            expr[-1] = as.call(lapply(as.list(expr)[-1], expand_loop_variables))
    } else {
        expr = as.call(lapply(as.list(expr), expand_loop_variables))
    }
    expr
}

add_expansion_to_loop = function(expr){

    loop_variable = expr[[2]]
    if(is.symbol(loop_variable) && grepl(",", as.character(loop_variable))){
        all_loop_variables = trimws(unlist(strsplit(as.character(loop_variable), split = ",")))
        expansion_expr = lapply(seq_along(all_loop_variables), function(item_num){
            curr_item = as.name(all_loop_variables[item_num])
            bquote(.(curr_item) <- .(loop_variable)[[.(item_num)]])
        })
        expansion_expr = as.call(c(list(quote(`{`)), expansion_expr))
        last_item = length(expr)
        expr[[last_item]] = bquote({
            .(expansion_expr)
            .(expr[[last_item]])
        })
    }
    expr
}

is_loop = function(expr){
    is.call(expr) || return(FALSE)
    first_item = expr[[1]]
    identical(first_item, quote(`for`)) ||identical(first_item, quote(`while`)) ||identical(first_item, quote(`repeat`))
}

is_for_loop = function(expr){
    is.call(expr) || return(FALSE)
    first_item = expr[[1]]
    identical(first_item, quote(`for`))
}

has_loop_inside = function(expr){
    is.call(expr) || return(FALSE)
    !is_loop(expr) || return(TRUE)
    first_elem = expr[[1]]
    for(item in SPECIAL_FUNCTIONS){
        if(identical(item, first_elem)) return(FALSE)
    }
    any(
        unlist(
            lapply(as.list(expr), has_loop_inside),
            recursive = TRUE,
            use.names = FALSE
        )
    )
}


add_assignment_to_loop = function(expr, result_exists = FALSE){
    last_item = length(expr)
    if(result_exists){
        expr[[last_item]] = bquote({
            .___curr = {.(expr[[last_item]])}
            if(inherits(.___curr, "exclude")){
                .___res[[.___counter + 1]] = NULL
            } else {
                .___counter = .___counter + 1
                if(!is.null(.___curr)){
                    .___res[[.___counter]] = .___curr
                }
            }

        })
    } else {
        expr[[last_item]] = bquote({

            .___curr = {.(expr[[last_item]])}
            if(!is.null(.___curr) && !inherits(.___curr, "exclude")){
                .___counter = .___counter + 1
                .___res[[.___counter]] = .___curr
            }

        })
    }
    expr
}

#' @rdname to_list
#' @export
alter = function(expr, data = NULL){
    expr = substitute(expr)
    is_loop(expr) ||
        stop(paste("argument should be expression with 'for', 'while' or 'repeat' but we have: ", deparse(expr, width.cutoff = 500)[1]))

    if(is.null(data)) {
        data = expr[[3]]
        if(is.call(data)){
            first = as.character(data[[1]])
            if(first %in% c("numerate", "enumerate", "mark", "lag_list")){
                data = data[[2]]
            }
        }

    }
    expr = expand_loop_variables(expr)
    expr = add_assignment_to_final_loops(expr, result_exists = TRUE)
    expr = substitute(local({
        .___res <- data
        .___counter <- 0  # initial list length
        expr
        .___res
    }))

    eval.parent(expr)

}


#' @rdname to_list
#' @export
to_df = function(expr, fill = TRUE){
    res = eval.parent(
        substitute(
            comprehenr::to_list(expr)
        )
    )
    for(i in seq_along(res)){
        if(!is.null(res[[i]]) && !is.data.frame(res[[i]])){
            res[[i]] = as.data.frame(as.list(res[[i]]))
        }
    }
    #
    if(fill){
        all_names = unique(unlist(lapply(res, names), use.names = FALSE))
        for(i in seq_along(res)){
            new_names = setdiff(all_names, names(res[[i]]))
            if(length(new_names)>0){
                res[[i]][,new_names] = NA
            }
        }
    }

    do.call(rbind, res)
}

# @rdname to_list
# @export
# to_dfr = to_df

# @rdname to_list
# @export
# to_dfc = function(expr = NULL){
#     res = eval.parent(
#         substitute(
#             comprehenr::to_list(expr)
#         )
#     )
#     as.data.frame(res)
# }


#' @rdname to_list
#' @export
exclude = function(){
    res = numeric(0)
    class(res) = "exclude"
    res
}
