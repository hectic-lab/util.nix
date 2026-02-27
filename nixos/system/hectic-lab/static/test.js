function webappInit() {
    console.log("Init start");
    window.Telegram.WebApp.BackButton.isVisible = true;
    window.Telegram.WebApp.backgroundColor = "#E60C0C";
    let initData = window.Telegram.WebApp.initData;
    if (initData) {
        console.log("InitData", initData);
        validate(initData);
    }
    console.log("Init end");
}

function validate(initData) {
    const urlencodedData = initData;

    const decodedData = decodeURIComponent(urlencodedData);

    fetch(
        "http://localhost:52022/rpc/webapp_auth",
        {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Content-Profile": "qutegate",
            },
            body: JSON.stringify({ raw_init_data: btoa(decodedData) }),
        }
    )
}

function waitForWebApp() {
    if (window.Telegram && window.Telegram.WebApp) {
        console.log("Telegram WebApp is available");
        webappInit();
    } else {
        console.log("Telegram WebApp is not available yet");
        setTimeout(waitForWebApp, 100);
    }
}

waitForWebApp();
