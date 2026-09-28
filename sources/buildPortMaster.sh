#!/bin/sh

FLAGS="-frelease -fdata-sections -ffunction-sections -fno-section-anchors -c -O2 -Wall -pipe -fsingle-precision-constant -fpredictive-commoning -fgcse-after-reload -ftree-vectorize -fvect-cost-model=cheap -ffast-math -fversion=PORTMASTER -fversion=BindSDL_Static -fversion=SDL_201 -fversion=SDL_Mixer_202 -I`pwd`/import"

rm import/*.o*
rm import/sdl/*.o*
rm import/bindbc/sdl/*.o*
rm src/abagames/util/*.o*
rm src/abagames/util/bulletml/*.o*
rm src/abagames/util/sdl/*.o*
rm src/abagames/tt/*.o*

cd import
find . -maxdepth 1 -name \*.d -type f -exec gdc $FLAGS \{\} \;
cd sdl
find . -maxdepth 1 -name \*.d -type f -exec gdc $FLAGS \{\} \;
cd ../bindbc/sdl
find . -maxdepth 1 -name \*.d -type f -exec gdc $FLAGS \{\} \;
cd ../../..

cd src/abagames/util
find . -maxdepth 1 -name \*.d -type f -exec gdc $FLAGS -I../.. \{\} \;
cd ../../..

cd src/abagames/util/bulletml
find . -maxdepth 1 -name \*.d -type f -exec gdc $FLAGS -I../../.. \{\} \;
cd ../../../..

cd src/abagames/util/sdl
find . -maxdepth 1 -name \*.d -type f -exec gdc $FLAGS -I../../.. \{\} \;
cd ../../../..

cd src/abagames/tt
find . -maxdepth 1 -name \*.d -type f -exec gdc $FLAGS -I../.. \{\} \;
cd ../../..

gdc -o Torus_Trooper -s -Wl,--gc-sections -static-libphobos import/*.o* import/sdl/*.o* import/bindbc/sdl/*.o* src/abagames/util/*.o* src/abagames/util/bulletml/*.o* src/abagames/util/sdl/*.o* src/abagames/tt/*.o* -L${BULLETML:-../bulletml}/src -Wl,--as-needed -Wl,-Bstatic -lbulletml -lGLU -Wl,-Bdynamic -lstdc++ -lGL -lSDL2_mixer -lSDL2
