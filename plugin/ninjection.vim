if exists("g:did_ninjection")
  finish
endif
let g:did_ninjection = 1
lua require("ninjection").setup()
