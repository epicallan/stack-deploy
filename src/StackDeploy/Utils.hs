module StackDeploy.Utils where

import StackDeploy.Prelude
import Stratosphere
import Stratosphere.Helpers

import qualified Data.Aeson                       as JSON
import qualified Data.Foldable                    as Foldable
import qualified Data.HashMap.Strict              as HashMap
import qualified Data.Vector                      as Vector
import qualified Network.AWS.CloudFormation.Types as CF

mkName :: Val Text -> Val Text
mkName name = Join "-" [awsStackName, name]

awsAccountId :: Val Text
awsAccountId = Ref "AWS::AccountId"

awsRegion :: Val Text
awsRegion = Ref "AWS::Region"

awsStackName :: Val Text
awsStackName = Ref "AWS::StackName"

getAtt :: Text -> Resource -> Val Text
getAtt name item = GetAtt (itemName item) name

getAttArn :: Resource -> Val Text
getAttArn = getAtt "Arn"

s3BucketBlockPublicAccess :: S3BucketPublicAccessBlockConfiguration
s3BucketBlockPublicAccess
  = s3BucketPublicAccessBlockConfiguration
  & sbpabcBlockPublicAcls       ?~ Literal True
  & sbpabcBlockPublicPolicy     ?~ Literal True
  & sbpabcIgnorePublicAcls      ?~ Literal True
  & sbpabcRestrictPublicBuckets ?~ Literal True

allowResourcePolicy
  :: JSON.ToJSON b
  => (JSON.Object -> Val Text -> a)
  -> b
  -> Text
  -> [Text]
  -> a
allowResourcePolicy constructor resources name actions
  = constructor (HashMap.singleton "Statement" statement) (Literal name)
  where
    statement :: JSON.Value
    statement = JSON.object
      [ ("Action",   JSON.Array $ Vector.fromList (JSON.toJSON <$> actions))
      , ("Effect",   "Allow")
      , ("Resource", JSON.toJSON resources)
      ]

assumeRole :: Text -> JSON.Object
assumeRole service = HashMap.fromList
  [ ("Version", JSON.String "2012-10-17")
  , ("Statement"
    , JSON.object
      [ ("Action",   "sts:AssumeRole")
      , ("Effect",   "Allow")
      , ("Principal", JSON.object [("Service", JSON.toJSON service)])
      ]
    )
  ]

dependencies :: [Resource] -> Resource -> Resource
dependencies deps res =
  res & resourceDependsOn ?~ (itemName <$> deps)

fetchOutput
  :: forall m . MonadFail m
  => CF.Stack
  -> Stratosphere.Output
  -> m Text
fetchOutput stack soutput =
  maybe
    (failOutputKey "missing")
    (maybe (failOutputKey "has no value") pure . view CF.oOutputValue)
    $ Foldable.find
      ((==) (pure key) . view CF.oOutputKey)
      (view CF.sOutputs stack)
  where
    key = view Stratosphere.outputName soutput

    failOutputKey :: Text -> m a
    failOutputKey message
      = failStack
      $ "Output " <> convertText key <> " " <> message

    failStack :: Text -> m a
    failStack message
      = fail
      . convertText
      $ "Stack: " <> view CF.sStackName stack <> " " <> message
