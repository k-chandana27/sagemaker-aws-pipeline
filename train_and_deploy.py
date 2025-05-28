# train_and_deploy.py
import sagemaker
from sagemaker.serializers import JSONSerializer
from sagemaker.deserializers import JSONDeserializer
import boto3
import pandas as pd
from sagemaker.sklearn.estimator import SKLearn
import os


def prepare_data(bucket_name, key):
    """
    Download CSV from S3, load into Pandas, and return features and labels.
    """
    s3 = boto3.client('s3')
    local_path = r"C:\Chandana-Learning\Chandana-Learning\error_logs.csv"
    
    s3.download_file(bucket_name, key, local_path)
    df = pd.read_csv(local_path)
    
    X = df['error_message'].tolist()
    y = df['recommended_action'].tolist()
    
    return X, y

def create_training_script(script_path='train_script.py'):
    """Create a local training script that the SKLearn Estimator can use."""
    script_code = '''
import argparse
import os
import pandas as pd
import joblib
import json
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline

def model_fn(model_dir):
    """Load model from the model_dir"""
    model_path = os.path.join(model_dir, "model.joblib")
    return joblib.load(model_path)

def input_fn(request_body, request_content_type):
    """Convert input data to format expected by the model"""
    if request_content_type == 'application/json':
        input_data = json.loads(request_body)
        # Handle both single string and list of strings
        if isinstance(input_data, str):
            return [input_data]
        elif isinstance(input_data, list):
            return input_data
        else:
            raise ValueError("Input must be a string or list of strings")
    raise ValueError(f"Unsupported content type: {request_content_type}")

def predict_fn(input_data, model):
    """Make prediction using model"""
    return model.predict(input_data)

def output_fn(prediction, accept):
    """Format prediction response"""
    if accept == 'application/json':
        return json.dumps(prediction.tolist())
    raise ValueError(f"Unsupported accept type: {accept}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-data-dir", type=str, default="/opt/ml/output/data")
    parser.add_argument("--model-dir", type=str, default="/opt/ml/model")
    parser.add_argument("--train", type=str, default="/opt/ml/input/data/train")
    args = parser.parse_args()

    # Load training data
    df = pd.read_csv(os.path.join(args.train, "train.csv"))
    X = df["error_message"].tolist()
    y = df["recommended_action"].tolist()

    # Create and train pipeline
    pipeline = Pipeline([
        ('vect', CountVectorizer()),
        ('clf', LogisticRegression(max_iter=1000))
    ])
    pipeline.fit(X, y)

    # Save model
    joblib.dump(pipeline, os.path.join(args.model_dir, "model.joblib"))
    print("Model training completed and saved.")
'''
    with open(script_path, 'w') as f:
        f.write(script_code)

def main():
    session = sagemaker.Session()
    bucket_name = "sagemaker-logs-poc"
    data_key = "data/error_logs.csv"
    
    # Download data to local /tmp, parse
    X, y = prepare_data(bucket_name, data_key)
    df = pd.DataFrame({"error_message": X, "recommended_action": y})
    
    # Save training data locally first
    #os.makedirs("poc_data", exist_ok=True)
    #training_data_path = "poc_data/train.csv"
    training_data_path = "train.csv"
    df.to_csv(training_data_path, index=False)

    #local_temp = "train.csv"
    #shutil.copy(r"C:\Chandana-Learning\Chandana-Learning\train.csv", local_temp)
    #s3_train_path = session.upload_data(local_temp, bucket=bucket_name, key_prefix="training")
    # Upload training data to S3
    s3_train_path = session.upload_data(training_data_path, bucket=bucket_name, key_prefix="training")
    
    # Create the training script
    create_training_script()
    
    # Create the SKLearn Estimator
    sklearn_estimator = SKLearn(
        entry_point="train_script.py",
        framework_version="1.0-1",
        instance_type="ml.m5.xlarge",
        instance_count=1,
        role=sagemaker.get_execution_role(),
        base_job_name="logs-error-model",
        sagemaker_session=session
    )
    
    # Fit using S3 path instead of local path
    sklearn_estimator.fit({'train': s3_train_path})
    
    # Deploy model with serializer configuration
    predictor = sklearn_estimator.deploy(
        initial_instance_count=1,
        instance_type="ml.m5.large",
        endpoint_name="logs-error-endpoint",
        serializer=sagemaker.serializers.JSONSerializer(),
        deserializer=sagemaker.deserializers.JSONDeserializer()
    )
    
    print("Model deployed successfully. Testing endpoint...")
    
    # Test the endpoint with a single prediction
    test_error = ["Error 500: Internal Server Error"]
    try:
        response = predictor.predict(test_error)
        print(f"Test successful!")
        print(f"Input Error: {test_error[0]}")
        print(f"Predicted Action: {response[0]}")
    except Exception as e:
        print(f"Error testing endpoint: {str(e)}")

if __name__ == "__main__":
    main()
