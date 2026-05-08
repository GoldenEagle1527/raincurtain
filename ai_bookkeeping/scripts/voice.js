// scripts/voice.js
'use strict';

var Voice = (function () {

  var mediaRecorder = null;
  var audioChunks = [];
  var isRecording = false;

  /** 检查浏览器是否支持录音 */
  function isSupported() {
    return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
  }

  /** 开始录音 */
  async function startRecording() {
    if (isRecording) return;
    if (!isSupported()) {
      throw new Error('当前环境不支持录音');
    }

    var stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    audioChunks = [];

    var mimeType = getSupportedMimeType();
    var options = mimeType ? { mimeType: mimeType } : {};
    mediaRecorder = new MediaRecorder(stream, options);

    mediaRecorder.addEventListener('dataavailable', function (e) {
      if (e.data.size > 0) {
        audioChunks.push(e.data);
      }
    });

    mediaRecorder.start();
    isRecording = true;
  }

  /** 停止录音并返回音频 Blob */
  function stopRecording() {
    return new Promise(function (resolve, reject) {
      if (!mediaRecorder || !isRecording) {
        reject(new Error('没有正在进行的录音'));
        return;
      }

      mediaRecorder.addEventListener('stop', function () {
        var mimeType = mediaRecorder.mimeType || 'audio/webm';
        var audioBlob = new Blob(audioChunks, { type: mimeType });
        cleanupStream();
        isRecording = false;
        audioChunks = [];
        resolve(audioBlob);
      });

      mediaRecorder.stop();
    });
  }

  /** 取消录音 */
  function cancelRecording() {
    if (mediaRecorder && isRecording) {
      mediaRecorder.stop();
      cleanupStream();
      isRecording = false;
      audioChunks = [];
    }
  }

  /** 释放麦克风流 */
  function cleanupStream() {
    if (mediaRecorder && mediaRecorder.stream) {
      mediaRecorder.stream.getTracks().forEach(function (track) {
        track.stop();
      });
    }
  }

  /** 获取浏览器支持的 MIME 类型 */
  function getSupportedMimeType() {
    var types = [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/mp4',
      'audio/ogg;codecs=opus'
    ];
    for (var i = 0; i < types.length; i++) {
      if (MediaRecorder.isTypeSupported(types[i])) {
        return types[i];
      }
    }
    return '';
  }

  /** 将 Blob 转换为 base64 字符串 */
  function blobToBase64(blob) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onloadend = function () {
        var base64 = reader.result.split(',')[1];
        resolve(base64);
      };
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }

  /** 获取录音状态 */
  function getIsRecording() {
    return isRecording;
  }

  return {
    isSupported: isSupported,
    startRecording: startRecording,
    stopRecording: stopRecording,
    cancelRecording: cancelRecording,
    blobToBase64: blobToBase64,
    getIsRecording: getIsRecording
  };

})();
