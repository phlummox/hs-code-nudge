
{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}

{- |

TODO: rewrite it all in C++, w/ CLI11 for command-line option parsing.

-}

module CodeNudge where

import Control.Monad.Reader

import qualified Data.List as L

import Foreign
import Foreign.C

import qualified Language.C.Inline.Cpp as C

import System.Environment
import System.Exit
import System.FilePath.Find
import System.IO

{-# ANN module ("HLint: ignore Use camelCase"::String) #-}

-- command-line arguments and options
data CmdArgs = CmdArgs {
    isRecursive :: Bool
  , beVerbose   :: Bool
  , files       :: [String]
  }
  deriving Show

data Vector a
data CxxString

C.context $
  C.cppCtx
  <> C.cppTypePairs [
          ("std::vector", [t|Vector|])
        , ("std::string", [t|CxxString|])
        ]

C.include "<cstdlib>"
C.include "<iostream>"
C.include "<vector>"
C.include "<sstream>"
C.include "<fstream>"

C.include "<srchilite/sourcehighlight.h>"
C.include "<srchilite/langmap.h>"
C.include "<srchilite/highlighteventlistener.h>"
C.include "<srchilite/highlightevent.h>"
C.include "<srchilite/highlighttoken.h>"

C.verbatim "\nconst std::string WHITESPACE = \" \\n\\r\\t\\f\\v\";\n"

type CmdReaderM = ReaderT CmdArgs IO

-- extract TODOs, FIXMEs etc from a file.
-- Returns either Nothing, or a non-null Ptr.
extract_todos ::
  String -> CmdReaderM (Maybe (Ptr (Vector CxxString)))
extract_todos fp = do
  verbose <- fromIntegral @Int @CInt . fromEnum <$> asks beVerbose
  let
    data_dir :: String
    data_dir = "/usr/share/source-highlight"
  liftIO $
    withCString data_dir $ \ddir_cstr -> -- directory where langmaps are
      withCString fp $ \fp_cstr -> do
        res <-
          [C.block| std::vector<std::string>* {
              using std::vector;
              using std::string;
              using srchilite::HighlightEvent;

              struct MyListener : public srchilite::HighlightEventListener {
                vector<string> todos;
                bool inside_comment = false;

                inline static bool isStartOfComment(const HighlightEvent &event) {
                  const auto &matched = event.token.matched;
                  return 
                        (event.type == HighlightEvent::ENTERSTATE)
                      && (matched.begin() != matched.end() )
                      && ( matched.begin()->first == "comment" );
                }

                inline static bool isEndOfComment(const HighlightEvent &event) {
                  const auto &matched = event.token.matched;
                  return 
                        (event.type == HighlightEvent::EXITSTATE)
                      && (matched.begin() != matched.end() )
                      && ( matched.begin()->first == "comment" );
                }

                inline static bool isEmptyMatch(const HighlightEvent &event) {
                  const auto &matched = event.token.matched;
                  return matched.begin() == matched.end();
                }

                inline static string ltrim(const string &s) {
                  size_t start = s.find_first_not_of(WHITESPACE);
                  return (start == string::npos) ? "" : s.substr(start);
                }

                inline static std::string rtrim(const std::string &s) {
                  size_t end = s.find_last_not_of(WHITESPACE);
                  return (end == std::string::npos) ? "" : s.substr(0, end + 1);
                }

                inline static std::string trim(const std::string &s) {
                    return rtrim(ltrim(s));
                }

                inline static bool startsWith(const std::string &s, const std::string &prefix) {
                  return s.rfind(prefix, 0) == 0;
                }

                virtual ~MyListener() {}
                virtual void notify(const HighlightEvent &event) {

                  if (isStartOfComment(event)) {
                    inside_comment = true;
                    return;
                  } else if (isEndOfComment(event)) {
                    inside_comment = false;
                    return;
                  }

                  if (! inside_comment || isEmptyMatch(event)) {
                    return;
                  }

                  // if still here, we're in a comment with >=1 match
                  const auto contents = trim(event.token.matched.begin()->second);
                  if (startsWith(contents, "TODO")
                      || startsWith(contents, "FIXME")
                      || startsWith(contents, "XXX")
                      || startsWith(contents, "NOTE")
                      || startsWith(contents, "ATTN")
                      )
                  {
                    todos.push_back(contents);
                  }
                }
              };

              srchilite::SourceHighlight highlighter("sexp.outlang");
              const char * data_dir = $(char * ddir_cstr);
              const char * input_file = $(char * fp_cstr);

              highlighter.setDataDir(  data_dir  );

              MyListener listener;
              highlighter.setHighlightEventListener(&listener);

              srchilite::LangMap langMap( data_dir, "lang.map");
              string detectedLang;
              if ( (detectedLang = langMap.getMappedFileNameFromFileName( input_file ) ) == "") {
                if ( $(int verbose) ) {
                  std::cerr << "couldn't detect lang for " << input_file << std::endl;
                }
                return nullptr;
              }

              // input and output stream. actually, we don't
              // need output stream, we just discard it...
              std::stringstream ss;
              std::ifstream ifs (input_file);

              // params = instr, outstr, lang, in filename
              highlighter.highlight(ifs, ss, detectedLang, input_file);

              std::vector<std::string>* res_vec = new std::vector<std::string>();
              *res_vec = listener.todos;
              return res_vec;
            }
          |]
        if res == nullPtr
          then return Nothing
          else return $ Just res

-- get all files specified by the CmdArgs
all_files :: CmdReaderM [FilePath]
all_files = do
  CmdArgs { isRecursive, files } <- ask
  if isRecursive
    then liftIO $ L.nub . join . sequence <$> mapM (find always (fileType /=? Directory)) files
    else return files

vec_size :: Ptr (Vector CxxString) -> CmdReaderM CSize
vec_size vec =
  liftIO [C.exp| size_t { $(std::vector<std::string>* vec)->size() } |]
{-# INLINE vec_size #-}

process_file :: String -> CmdReaderM ()
process_file filepath =
  extract_todos filepath >>= \case
    Nothing -> return ()
    Just todos ->
      vec_size todos >>= \case
        0 -> return ()
        _ ->  liftIO $ do
                 putStrLn $ filepath <> ":"
                 [C.block| void {
                    struct bogus { }; 

                    using std::vector;
                    using std::string;
                    const auto todos = $(std::vector<std::string>* todos);
                    for( auto && todo : *todos) {
                      string x = todo;
                      std::cout << "  " << x << std::endl;
                    }
                  }
                 |]


process_files :: CmdReaderM ()
process_files =
    mapM_ process_file =<< all_files




main :: IO ()
main = do
  args <- getArgs
  when (null args) $ do
    hPutStrLn stderr $ unlines [
        "code-nudge: couldn't parse command line args."
      , ""
      , "usage:"
      , "  code-nudge [-r] [-v] [FILE...]"
      , ""
      , "-r -- process directories recursively"
      , "-v -- print a warning if a file-type couldn't be detected"
      ]
    exitFailure
  let beVerbose   = "-v" `elem` take 2 args
      isRecursive = "-r" `elem` take 2 args
      files       = (if beVerbose
                     then drop 1
                     else id ) $
                        (if isRecursive
                        then drop 1
                        else id) args
      cmdArgs = CmdArgs{..}
  --putStrLn $ "cmdArgs = " <> show cmdArgs
  runReaderT process_files cmdArgs





