const multi = require('multiformats');

function test() {
    const v1 = multi.CID.parse('baga6ea4seaqe26xbu4mge42rfrogtu27l7htfojescjsg6lvfaoinhhnblo42ba')

    console.log(v1)
}

test()