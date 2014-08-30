CORPUS="/home/kevin/Development/varnam-tools/transliteration_accuracy/ml/novel1.txt"
BASE="/home/kevin/Development/varnam-tools/"
MASTER="/home/kevin/Development/libvarnam-upstream-master/"
STEMMER="/home/kevin/Development/libvarnam/"

sudo rm $HOME/.local/share/varnam/suggestions/*

echo "Building Master"
cd $MASTER
cmake .
make clean
make
sudo make install
varnamc -c schemes/ml
sudo make install
gcc review.c -lvarnam -o learner
echo "Learning corpus"
varnamc -s ml --learn-from $CORPUS
echo "Checking Accuracy"
cd $BASE
ruby stemmer_accuracy.rb -s ml -f transliteration_accuracy/ml/novel2.txt > result_master.txt

sudo rm $HOME/.local/share/varnam/suggestions/*

echo "Building stemmer"
cd $STEMMER
cmake .
make clean
make
sudo make install
varnamc -c schemes/ml
sudo make install
gcc review.c -lvarnam -o learner
echo "Learning corpus"
varnamc -s ml --learn-from $CORPUS
echo "Checking accuracy"
cd $BASE
ruby stemmer_accuracy.rb -s ml -f transliteration_accuracy/ml/novel2.txt > result_stemmer.txt